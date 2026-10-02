# Housing Data Cleaning & ETL (PostgreSQL)

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-316192?logo=postgresql&logoColor=white)
![Status](https://img.shields.io/badge/status-complete-2E6F95)

A SQL-based data cleaning and ETL project that takes a raw housing
transactions dataset, loads it into PostgreSQL, identifies and fixes
common real-world data-quality issues, and uses the cleaned dataset to
answer business questions.

The project focuses on practical SQL skills used in data analyst and
ETL workflows: staging, validation, type casting, string/date parsing,
duplicate removal, and analytical querying with window functions.

---

## Tools & Technologies

- PostgreSQL
- pgAdmin
- SQL
- CSV

---

## ETL Workflow

```text
Raw CSV File
     ↓
Extract
     ↓
PostgreSQL (housing_data_raw, all TEXT columns)
     ↓
Transform
     ↓
Cleaned Housing Dataset
     ↓
Load / Export
     ↓
Clean CSV Output
```

### Extract

The source CSV was imported into PostgreSQL and staged in
`housing_data_raw`.

Every column was staged as `TEXT`, intentionally. Loading straight into
typed columns (`NUMERIC`, `INTEGER`, ...) fails on this dataset: several
numeric-looking fields (`acreage`, `year_built`, `bedrooms`, bathroom
counts) have blank values, and some `sale_price` values are formatted
as currency strings (`"$120,000"`). Staging as `TEXT` first means no
rows are lost on import — the columns are cleaned and cast to their
final types later (step 11 of the SQL script), once the bad values have
been identified and handled.

### Transform

1. Data validation
2. Date standardization
3. Populating missing property addresses
4. Splitting property addresses
5. Splitting owner addresses
6. Standardizing categorical values
7. Removing duplicate records
8. Removing redundant columns
9. Final data-quality checks
10. **Finalizing column data types** (TEXT → INTEGER / NUMERIC / VARCHAR / SMALLINT)

### Load

The cleaned table is exported as `data/housing_data_clean.csv`, the
final output of the ETL process.

---

## Dataset Overview

The dataset contains Nashville-area housing property and sale records.

**`ParcelID`** identifies the underlying property or land parcel — the
same property can appear in multiple records.

**`UniqueID`** identifies an individual record/transaction. Two records
can share a `ParcelID` but have different `UniqueID` values, since the
same property can be sold more than once. This distinction mattered
most when filling in missing property addresses.

---

## Data Cleaning Process

### 1. Data Validation

Confirmed the dataset loaded successfully with the expected columns.

**Initial row count: 56,477 records**

### 2. Date Standardization

`sale_date` was stored as text (e.g. `"April 9, 2013"`). It was
converted to a native `DATE` using `TO_DATE()`:

```sql
ALTER TABLE housing_data_raw
ALTER COLUMN sale_date TYPE DATE
USING TO_DATE(sale_date, 'Month DD, YYYY');
```

### 3. Populate Missing Property Addresses

**29 records** had a missing `property_address`. Since multiple records
can share a `ParcelID`, a self-join matched each record missing an
address to another record for the *same parcel* that already had one,
and used it to fill the gap:

```sql
UPDATE housing_data_raw AS a
SET property_address = b.property_address
FROM housing_data_raw AS b
WHERE a.parcel_id = b.parcel_id
  AND a.unique_id <> b.unique_id
  AND a.property_address IS NULL
  AND b.property_address IS NOT NULL;
```

**Result: 0 remaining missing property addresses**

### 4. Split Property Address

`property_address` contained both street address and city
(`"1808 FOX CHASE DR, GOODLETTSVILLE"`). Split into
`property_split_address` and `property_split_city` using
`SPLIT_PART()` and `TRIM()`.

### 5. Split Owner Address

`owner_address` contained address, city, and state. Split into
`owner_split_address`, `owner_split_city`, and `owner_split_state`.

### 6. Standardize Sold-As-Vacant Values

`sold_as_vacant` mixed `Y`/`N` with `Yes`/`No`. A `CASE` statement
standardized every value to `Yes`/`No`; values that were already
standardized were left unchanged.

### 7. Remove Duplicate Records

Duplicates were identified with `ROW_NUMBER()` partitioned by
`parcel_id`, `property_address`, `sale_price`, `sale_date`, and
`legal_reference`, keeping the first record (lowest `unique_id`) in
each group and discarding the rest.

**Duplicate records removed: 104 → Final records: 56,373**

### 8. Remove Redundant Columns

Dropped the original columns replaced by cleaned/split versions:
`owner_address`, `tax_district`, `property_address`. `sale_date` was
kept since it was converted in place from `TEXT` to `DATE`.

### 9. Final Data Quality Checks

Confirmed the final row count and reviewed every cleaned field.

### 10. Finalize Column Data Types

The staging table kept every column as `TEXT` (see *Extract*, above).
With the data now cleaned, each column was cast to its final type:

| Column(s) | Final type | Why |
|---|---|---|
| `unique_id` | `INTEGER` | numeric record ID |
| `parcel_id` | `VARCHAR(20)` | contains spaces/periods (`007 00 0 125.00`), not numeric |
| `land_use`, `sold_as_vacant` | `VARCHAR` | categorical text |
| `sale_price`, `acreage`, `land_value`, `building_value`, `total_value` | `NUMERIC` | currency / decimal values |
| `legal_reference` | `VARCHAR` | alphanumeric reference code |
| `owner_name`, `*_split_address`, `*_split_city`, `*_split_state` | `VARCHAR` | free-text / parsed address fields |
| `year_built`, `bedrooms`, `full_bath`, `half_bath` | `SMALLINT` | small integer counts |

Two issues had to be handled before the casts would succeed:

- **Blank values**: `acreage`, `land_value`, `building_value`,
  `total_value`, `year_built`, `bedrooms`, `full_bath`, and `half_bath`
  all contain blank strings for records with no data on file. `NULLIF()`
  converts these to `NULL` before casting, so the `ALTER COLUMN`
  statements don't fail on empty text.
- **Currency formatting**: 12 `sale_price` values were stored as
  `"$120,000"` instead of plain numbers. `REPLACE()` strips the `$`
  and `,` characters before the `NUMERIC` cast.

```sql
UPDATE housing_data_raw
SET sale_price = REPLACE(REPLACE(sale_price, '$', ''), ',', '');

ALTER TABLE housing_data_raw
    ALTER COLUMN unique_id TYPE INTEGER USING unique_id::INTEGER,
    ALTER COLUMN sale_price TYPE NUMERIC(12,2) USING NULLIF(sale_price, '')::NUMERIC,
    ALTER COLUMN acreage TYPE NUMERIC(10,2) USING NULLIF(acreage, '')::NUMERIC,
    ALTER COLUMN year_built TYPE SMALLINT USING NULLIF(year_built, '')::SMALLINT;
    -- (full statement in sql/housing_data_cleaning.sql)
```

---

## Key SQL Techniques Demonstrated

`SELECT` · `COUNT()` · `WHERE` · `GROUP BY` · `ORDER BY` · `CASE` ·
`UPDATE` / `SET` · `ALTER TABLE` / `ALTER COLUMN` · `TO_DATE()` ·
`SPLIT_PART()` · `TRIM()` · `REPLACE()` · `NULLIF()` · type casting ·
self-joins · Common Table Expressions (CTEs) · `ROW_NUMBER()` /
`PARTITION BY` (window functions) · duplicate detection and removal ·
column removal · `LAG()` · `PERCENTILE_CONT()` · `FILTER` · `HAVING`

---

## Results

| Metric | Result |
|---|---|
| Initial records | 56,477 |
| Missing property addresses identified | 29 |
| Remaining missing property addresses | 0 |
| Currency-formatted `sale_price` values fixed | 12 |
| Duplicate records removed | 104 |
| Final records | 56,373 |

---

## Analysis & Key Findings

Beyond cleaning, `sql/housing_data_analysis.sql` answers six business
questions against the cleaned dataset, using window functions
(`LAG()`, `ROW_NUMBER()`), CTEs, `PERCENTILE_CONT()`, and `FILTER`.
Results below are computed from `data/housing_data_clean.csv`.

**1. Sales volume and average price by year**

| Year | Total sales | Avg sale price | YoY change |
|---|---|---|---|
| 2013 | 11,292 | $244,577 | — |
| 2014 | 14,274 | $334,352 | +36.7% |
| 2015 | 16,734 | $399,936 | +19.6% |
| 2016 | 14,071 | $301,071 | -24.7% |

*Two records carry a `sale_date` in 2019, well outside this range —
flagged as a likely data-entry anomaly rather than a real trend, and
excluded from the table above.*

**2. Highest average sale price by city** (min. 100 sales)

| City | Total sales | Avg sale price |
|---|---|---|
| Nashville | 40,216 | $366,625 |
| Brentwood | 1,696 | $312,258 |
| Goodlettsville | 735 | $289,639 |
| Nolensville | 494 | $287,144 |
| Antioch | 6,286 | $252,755 |

**3. Vacant vs. non-vacant sales**

| Sold as vacant | Total sales | Avg sale price |
|---|---|---|
| No | 51,704 | $329,179 |
| Yes | 4,669 | $309,186 |

Vacant land sold for only ~6% less than built properties on average —
land value is a large share of total price in this market.

**4. Average sale price by bedroom count**

| Bedrooms | Total sales | Avg sale price |
|---|---|---|
| 1 | 102 | $166,416 |
| 2 | 5,092 | $174,743 |
| 3 | 12,852 | $226,581 |
| 4 | 4,848 | $400,552 |
| 5 | 870 | $734,776 |
| 6 | 243 | $646,667 |

Price climbs steadily with bedroom count through 5 bedrooms; the dip
at 6 bedrooms is likely sample-size noise (only 243 sales).

**5. Repeat sales — price change per parcel**

Of the 56,373 cleaned records, **7,146 parcels sold more than once**.
Comparing each parcel's first sale to its most recent sale:

- Median price change: **+43.8%**
- **88.0%** of repeat-sale parcels sold for more the second time

(Median is reported instead of mean because a small number of parcels
jump by 1,000%+ — almost certainly vacant land that was later sold
again after a house was built on it — which would otherwise skew the
average.)

**6. Land use: transaction count and total dollar volume**

| Land use | Total sales | Total dollar volume |
|---|---|---|
| Single Family | 34,119 | $9.57B |
| Residential Condo | 14,064 | $6.14B |
| Vacant Residential Land | 3,540 | $1.33B |
| Vacant Res Land | 1,549 | $370M |
| Duplex | 1,372 | $357M |

---

## Project Structure

```text
housing-data-sql-cleaning/
│
├── README.md
│
├── sql/
│   ├── housing_data_cleaning.sql       -- full cleaning script, run in order
│   └── housing_data_analysis.sql       -- business-question queries against the cleaned data
│
└── data/
    ├── housing_data_raw.csv            -- original source data
    └── housing_data_clean.csv          -- final cleaned output
```

## Reproducing the Results

1. Create a PostgreSQL database and run `sql/housing_data_cleaning.sql`
   top to bottom against `data/housing_data_raw.csv` (imported into
   `housing_data_raw` as the first step of the script).
2. Export the final `housing_data_cleaned` table to CSV for the cleaned
   output:
   ```
   \copy housing_data_cleaned TO 'housing_data_clean.csv' WITH (FORMAT CSV, HEADER);
   ```

`data/housing_data_clean.csv` in this repo is a direct export of that
table — both `sql/housing_data_cleaning.sql` and
`sql/housing_data_analysis.sql` were run against a live PostgreSQL
database, and every number in this README was read back from the
query output.

---

## Project Outcome

This project demonstrates a practical PostgreSQL data-cleaning
workflow from raw imported data to a cleaned, properly-typed dataset:
data validation, date standardization, missing-value handling via
self-joins, address parsing, categorical standardization, duplicate
detection and removal, redundant-column removal, and final type
casting — followed by an analysis layer that turns the cleaned data
into answered business questions using window functions, CTEs, and
aggregate queries.

---

## Author
**Elnaz Khodadadi** — Data Analyst | SQL · Power BI · Excel
GitHub: [@ekhodada](https://github.com/ekhodada) · LinkedIn: [elnaz-khodadadi](https://www.linkedin.com/in/elnaz-khodadadi-547868a6/)
