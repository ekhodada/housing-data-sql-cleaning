-- ============================================================
-- HOUSING DATA CLEANING & ETL
-- PostgreSQL
-- ============================================================
-- Objective:
-- Clean and transform raw housing data into a structured,
-- analysis-ready dataset using PostgreSQL.
-- ============================================================


-- ============================================================
-- 1. RAW DATA STAGING
-- ============================================================

-- Raw source data is loaded from CSV into housing_data_raw.
-- All source fields are initially stored as TEXT to preserve
-- the original data before transformation. Importing directly
-- into typed columns (NUMERIC, INTEGER, ...) fails on this data
-- set because many numeric-looking columns contain blank values
-- and a handful of currency fields are formatted as "$120,000".
-- Staging everything as TEXT avoids losing rows on import; the
-- columns are cast to their final types later, after cleaning
-- (see step 11).

CREATE TABLE housing_data_raw (
    unique_id TEXT,
    parcel_id TEXT,
    land_use TEXT,
    property_address TEXT,
    sale_date TEXT,
    sale_price TEXT,
    legal_reference TEXT,
    sold_as_vacant TEXT,
    owner_name TEXT,
    owner_address TEXT,
    acreage TEXT,
    tax_district TEXT,
    land_value TEXT,
    building_value TEXT,
    total_value TEXT,
    year_built TEXT,
    bedrooms TEXT,
    full_bath TEXT,
    half_bath TEXT
);


-- ============================================================
-- 2. DATA VALIDATION
-- ============================================================

-- Validate row count after ingestion.

SELECT COUNT(*) AS total_rows
FROM housing_data_raw;

-- Result: 56,477 rows


-- Inspect the raw dataset.

SELECT *
FROM housing_data_raw
LIMIT 10;


-- ============================================================
-- 3. DATA TYPE STANDARDIZATION
-- ============================================================

-- Preview the sale date conversion before modifying the column.

SELECT
    sale_date,
    TO_DATE(sale_date, 'Month DD, YYYY') AS standardized_sale_date
FROM housing_data_raw
LIMIT 10;


-- Convert sale_date from TEXT to DATE.

ALTER TABLE housing_data_raw
ALTER COLUMN sale_date TYPE DATE
USING TO_DATE(sale_date, 'Month DD, YYYY');


-- Validate the standardized date values.

SELECT sale_date
FROM housing_data_raw
LIMIT 10;

-- ============================================================
-- 4. POPULATE MISSING PROPERTY ADDRESSES
-- ============================================================

-- Identify records with missing property addresses.

SELECT
    unique_id,
    parcel_id,
    property_address
FROM housing_data_raw
WHERE property_address IS NULL;

-- Result: 29 records with a missing property_address


-- Compare records with the same ParcelID to identify
-- available property addresses for missing values.

SELECT
    a.parcel_id,
    a.unique_id AS missing_unique_id,
    b.unique_id AS matching_unique_id,
    b.property_address AS matching_address
FROM housing_data_raw AS a
JOIN housing_data_raw AS b
    ON a.parcel_id = b.parcel_id
    AND a.unique_id <> b.unique_id
WHERE a.property_address IS NULL
  AND b.property_address IS NOT NULL
ORDER BY a.parcel_id;


-- Populate missing property addresses using the matching
-- address from another record with the same ParcelID.

UPDATE housing_data_raw AS a
SET property_address = b.property_address
FROM housing_data_raw AS b
WHERE a.parcel_id = b.parcel_id
  AND a.unique_id <> b.unique_id
  AND a.property_address IS NULL
  AND b.property_address IS NOT NULL;


-- Verify that missing property addresses were populated.

SELECT COUNT(*) AS remaining_missing_addresses
FROM housing_data_raw
WHERE property_address IS NULL;

-- Result: 0 remaining missing property addresses

-- ============================================================
-- 5. SPLIT PROPERTY ADDRESS
-- ============================================================

-- Create separate columns for property address and city.

ALTER TABLE housing_data_raw
ADD COLUMN property_split_address TEXT;

ALTER TABLE housing_data_raw
ADD COLUMN property_split_city TEXT;


-- Split the property address at the comma.
-- SPLIT_PART() extracts the address and city components,
-- while TRIM() removes extra spaces around the extracted values.

UPDATE housing_data_raw
SET property_split_address = TRIM(SPLIT_PART(property_address, ',', 1)),
    property_split_city = TRIM(SPLIT_PART(property_address, ',', 2));

-- Verify the split property address fields.

SELECT *
FROM housing_data_raw
LIMIT 10;

-- ============================================================
-- 6. SPLIT OWNER ADDRESS
-- ============================================================

-- Create separate columns for owner address, city, and state.

ALTER TABLE housing_data_raw
ADD COLUMN owner_split_address TEXT;

ALTER TABLE housing_data_raw
ADD COLUMN owner_split_city TEXT;

ALTER TABLE housing_data_raw
ADD COLUMN owner_split_state TEXT;


-- Split the owner address into address, city, and state.
-- SPLIT_PART() separates the values using commas,
-- while TRIM() removes extra spaces.

UPDATE housing_data_raw
SET owner_split_address = TRIM(SPLIT_PART(owner_address, ',', 1)),
    owner_split_city = TRIM(SPLIT_PART(owner_address, ',', 2)),
    owner_split_state = TRIM(SPLIT_PART(owner_address, ',', 3));


-- Verify the split owner address fields.

SELECT *
FROM housing_data_raw
LIMIT 10;

-- ============================================================
-- 7. STANDARDIZE SOLD AS VACANT VALUES
-- ============================================================

-- Review the existing values and their frequencies.

SELECT
    sold_as_vacant,
    COUNT(*) AS record_count
FROM housing_data_raw
GROUP BY sold_as_vacant
ORDER BY record_count DESC;


-- Standardize Y/N values to Yes/No.

UPDATE housing_data_raw
SET sold_as_vacant = CASE
    WHEN sold_as_vacant = 'Y' THEN 'Yes'
    WHEN sold_as_vacant = 'N' THEN 'No'
    ELSE sold_as_vacant
END;


-- Verify the standardized values.

SELECT
    sold_as_vacant,
    COUNT(*) AS record_count
FROM housing_data_raw
GROUP BY sold_as_vacant
ORDER BY record_count DESC;

-- ============================================================
-- 8. REMOVE DUPLICATES
-- ============================================================

-- Identify duplicate records based on property and sale fields.

WITH duplicate_records AS (
    SELECT
        unique_id,
        ROW_NUMBER() OVER (
            PARTITION BY
                parcel_id,
                property_address,
                sale_price,
                sale_date,
                legal_reference
            ORDER BY unique_id
        ) AS row_num
    FROM housing_data_raw
)

SELECT *
FROM duplicate_records
WHERE row_num > 1;


-- Remove duplicate records while keeping the first occurrence.

WITH duplicate_records AS (
    SELECT
        unique_id,
        ROW_NUMBER() OVER (
            PARTITION BY
                parcel_id,
                property_address,
                sale_price,
                sale_date,
                legal_reference
            ORDER BY unique_id
        ) AS row_num
    FROM housing_data_raw
)
DELETE FROM housing_data_raw
WHERE unique_id IN (
    SELECT unique_id
    FROM duplicate_records
    WHERE row_num > 1
);


-- Verify the remaining number of records.

SELECT COUNT(*) AS total_rows
FROM housing_data_raw;

-- Result: 104 duplicates removed, 56,373 records remaining


-- ============================================================
-- 9. REMOVE REDUNDANT COLUMNS
-- ============================================================

-- Remove original columns that have been replaced by
-- cleaned or split columns.

ALTER TABLE housing_data_raw
DROP COLUMN owner_address,
DROP COLUMN tax_district,
DROP COLUMN property_address;

-- ============================================================
-- 10. FINAL DATA QUALITY CHECKS
-- ============================================================

-- Check the final number of records.

SELECT COUNT(*) AS total_rows
FROM housing_data_raw;


-- Check for remaining NULL property addresses.

SELECT COUNT(*) AS missing_property_addresses
FROM housing_data_raw
WHERE property_split_address IS NULL;


-- Check for remaining NULL owner addresses.

SELECT COUNT(*) AS missing_owner_addresses
FROM housing_data_raw
WHERE owner_split_address IS NULL;

-- Review the final cleaned dataset.

SELECT *
FROM housing_data_raw
LIMIT 10;

-- ============================================================
-- 11. FINALIZE COLUMN DATA TYPES
-- ============================================================

-- All staging columns were loaded as TEXT so the raw CSV could be
-- imported without failing on blank values or inconsistent
-- formatting (see step 1). Now that the data has been validated
-- and cleaned, cast each column to an appropriate type.

-- A small number of sale_price values are stored with currency
-- formatting (e.g. "$120,000") rather than a plain number. These
-- must be stripped before the column can be cast to NUMERIC.

SELECT unique_id, sale_price
FROM housing_data_raw
WHERE sale_price ~ '[\$,]';

-- Result: 12 records with currency-formatted sale_price values

UPDATE housing_data_raw
SET sale_price = REPLACE(REPLACE(sale_price, '$', ''), ',', '');


-- Cast each column to its final data type. NULLIF() converts
-- blank strings to NULL first so numeric/integer casts don't fail
-- on the empty values left by missing acreage, year_built,
-- bedrooms, and bathroom counts.

ALTER TABLE housing_data_raw
    ALTER COLUMN unique_id TYPE INTEGER USING unique_id::INTEGER,
    ALTER COLUMN parcel_id TYPE VARCHAR(20),
    ALTER COLUMN land_use TYPE VARCHAR(50),
    ALTER COLUMN sale_price TYPE NUMERIC(12,2) USING NULLIF(sale_price, '')::NUMERIC,
    ALTER COLUMN legal_reference TYPE VARCHAR(30),
    ALTER COLUMN sold_as_vacant TYPE VARCHAR(5),
    ALTER COLUMN owner_name TYPE VARCHAR(100),
    ALTER COLUMN acreage TYPE NUMERIC(10,2) USING NULLIF(acreage, '')::NUMERIC,
    ALTER COLUMN land_value TYPE NUMERIC(12,2) USING NULLIF(land_value, '')::NUMERIC,
    ALTER COLUMN building_value TYPE NUMERIC(12,2) USING NULLIF(building_value, '')::NUMERIC,
    ALTER COLUMN total_value TYPE NUMERIC(12,2) USING NULLIF(total_value, '')::NUMERIC,
    ALTER COLUMN year_built TYPE SMALLINT USING NULLIF(year_built, '')::SMALLINT,
    ALTER COLUMN bedrooms TYPE SMALLINT USING NULLIF(bedrooms, '')::SMALLINT,
    ALTER COLUMN full_bath TYPE SMALLINT USING NULLIF(full_bath, '')::SMALLINT,
    ALTER COLUMN half_bath TYPE SMALLINT USING NULLIF(half_bath, '')::SMALLINT,
    ALTER COLUMN property_split_address TYPE VARCHAR(100),
    ALTER COLUMN property_split_city TYPE VARCHAR(50),
    ALTER COLUMN owner_split_address TYPE VARCHAR(100),
    ALTER COLUMN owner_split_city TYPE VARCHAR(50),
    ALTER COLUMN owner_split_state TYPE VARCHAR(5);


-- Verify the final column types.

SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'housing_data_raw'
ORDER BY ordinal_position;

-- ============================================================
-- 12. PREPARE CLEANED DATA FOR EXPORT
-- ============================================================

-- Rename the transformed table to represent the final
-- cleaned dataset.

ALTER TABLE housing_data_raw
RENAME TO housing_data_cleaned;
