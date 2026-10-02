-- ============================================================
-- HOUSING DATA ANALYSIS
-- PostgreSQL
-- ============================================================
-- Business questions answered against the cleaned
-- housing_data_cleaned table produced by
-- housing_data_cleaning.sql.
-- ============================================================


-- ============================================================
-- 1. Sales volume and average price by year (YoY % change)
-- ============================================================

SELECT
    EXTRACT(YEAR FROM sale_date) AS sale_year,
    COUNT(*) AS total_sales,
    ROUND(AVG(sale_price), 0) AS avg_sale_price,
    ROUND(
        (AVG(sale_price) - LAG(AVG(sale_price)) OVER (ORDER BY EXTRACT(YEAR FROM sale_date)))
        / LAG(AVG(sale_price)) OVER (ORDER BY EXTRACT(YEAR FROM sale_date)) * 100,
    1) AS yoy_pct_change
FROM housing_data_cleaned
GROUP BY sale_year
ORDER BY sale_year;


-- ============================================================
-- 2. Top cities by average sale price (minimum 100 sales)
-- ============================================================

SELECT
    property_split_city,
    COUNT(*) AS total_sales,
    ROUND(AVG(sale_price), 0) AS avg_sale_price
FROM housing_data_cleaned
GROUP BY property_split_city
HAVING COUNT(*) >= 100
ORDER BY avg_sale_price DESC
LIMIT 10;


-- ============================================================
-- 3. Vacant vs. non-vacant sales: average price
-- ============================================================

SELECT
    sold_as_vacant,
    COUNT(*) AS total_sales,
    ROUND(AVG(sale_price), 0) AS avg_sale_price
FROM housing_data_cleaned
GROUP BY sold_as_vacant;


-- ============================================================
-- 4. Average sale price by bedroom count
-- ============================================================

SELECT
    bedrooms,
    COUNT(*) AS total_sales,
    ROUND(AVG(sale_price), 0) AS avg_sale_price
FROM housing_data_cleaned
WHERE bedrooms BETWEEN 1 AND 6
GROUP BY bedrooms
ORDER BY bedrooms;


-- ============================================================
-- 5. Repeat sales: price change between a parcel's first and
--    most recent sale
-- ============================================================

WITH parcel_sales AS (
    SELECT
        parcel_id,
        sale_price,
        -- unique_id is a tiebreaker: some parcels have two sales recorded
        -- on the same sale_date, and ROW_NUMBER() needs a deterministic
        -- order to consistently pick the "first"/"last" sale.
        ROW_NUMBER() OVER (PARTITION BY parcel_id ORDER BY sale_date ASC, unique_id ASC) AS sale_order,
        ROW_NUMBER() OVER (PARTITION BY parcel_id ORDER BY sale_date DESC, unique_id DESC) AS sale_order_desc,
        COUNT(*) OVER (PARTITION BY parcel_id) AS sale_count
    FROM housing_data_cleaned
),
first_last AS (
    SELECT
        parcel_id,
        MAX(sale_count) AS sale_count,
        MAX(CASE WHEN sale_order = 1 THEN sale_price END) AS first_sale_price,
        MAX(CASE WHEN sale_order_desc = 1 THEN sale_price END) AS last_sale_price
    FROM parcel_sales
    GROUP BY parcel_id
)
SELECT
    COUNT(*) AS parcels_with_repeat_sales,
    -- PERCENTILE_CONT() returns DOUBLE PRECISION; ROUND() only accepts
    -- NUMERIC, so the result must be cast before rounding.
    ROUND(
        (PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY (last_sale_price - first_sale_price) / NULLIF(first_sale_price, 0) * 100
        ))::NUMERIC, 1
    ) AS median_pct_price_change,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE last_sale_price > first_sale_price) / COUNT(*), 1
    ) AS pct_parcels_price_increased
FROM first_last
WHERE sale_count > 1;


-- ============================================================
-- 6. Land use: transaction count and total dollar volume
-- ============================================================

SELECT
    land_use,
    COUNT(*) AS total_sales,
    SUM(sale_price) AS total_dollar_volume
FROM housing_data_cleaned
GROUP BY land_use
ORDER BY total_dollar_volume DESC
LIMIT 8;
