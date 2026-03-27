-- INVENTORY ANALYSIS PROJECT Q1 2026
-- Step 1: Data Cleaning and Inventory Caculation
## Double check data type
SELECT column_name, data_type
FROM `carbon-watch-456400-u1.supply_chain_project.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'supply_info';

## Double check duplicate
SELECT
  Date, SKU_ID, Warehouse_ID, count(*) as duplicate_count
FROM `carbon-watch-456400-u1.supply_chain_project.supply_info_cleaned`
GROUP BY 1, 2, 3
HAVING count(*) > 1;

## Double check null
SELECT
  count(*) as total_rows,
  countif(SKU_ID IS NULL) as missing_sku,
  countif(Inventory_Level IS NULL) as missing_inventory,
  min(Date) as start_date,
  max(Date) as end_date
FROM `carbon-watch-456400-u1.supply_chain_project.supply_info`

## Create inventory clean data
CREATE OR REPLACE TABLE `carbon-watch-456400-u1.supply_chain_project.supply_info_cleaned` AS
SELECT
  Date,
  UPPER(TRIM(SKU_ID)) as sku_id,
  Warehouse_ID,
  Region,
  Units_Sold,
  Inventory_Level,
  GREATEST(0, Inventory_Level) as inventory_level_fixed,
  Unit_Cost,
  Unit_Price,
  (GREATEST(0, Inventory_Level) * Unit_Cost) as inventory_value,
  Supplier_Lead_Time_Days,
  Reorder_Point,
  Stockout_Flag
FROM `carbon-watch-456400-u1.supply_chain_project.supply_info`
WHERE SKU_ID IS NOT NULL
  AND Unit_Price > 0;

--Step 2: Classify ABC based on inventory value
CREATE OR REPLACE TABLE `carbon-watch-456400-u1.supply_chain_project.abc_analysis_result` AS
WITH sku_value AS (
  SELECT
  sku_id,
  SUM(inventory_value) as total_sku_value
  FROM `carbon-watch-456400-u1.supply_chain_project.supply_info_cleaned`
  GROUP BY 1
),
cumulative_calculation AS (
  SELECT
    sku_id,
    total_sku_value,
    SUM(total_sku_value) OVER (ORDER BY total_sku_value DESC) / SUM(total_sku_value) OVER () as cumulative_pct
  FROM sku_value
)
SELECT
  sku_id,
  total_sku_value,
  cumulative_pct,
  CASE
    WHEN cumulative_pct <= 0.8 THEN 'A'
    WHEN cumulative_pct <= 0.95 THEN 'B'
    ELSE 'C'
  END AS abc_class
FROM cumulative_calculation

-- Step 3: Determine Stock Status (Below Reorder Point)
CREATE OR REPLACE TABLE `carbon-watch-456400-u1.supply_chain_project.final_inventory_kpi` AS
SELECT
    i.Date,
    i.sku_id,
    i.Warehouse_ID,
    i.Region,
    abc.abc_class,
    i.inventory_level_fixed as current_stock,
    i.Reorder_Point,
    i.Units_Sold,
    i.Unit_Price,
    i.inventory_value,
    CASE
      WHEN i.inventory_level_fixed <= 0 THEN 'Out of Stock'
      WHEN i.inventory_level_fixed <= i.Reorder_Point THEN 'Below Reorder Point (Restock!)'
      ELSE 'Healthy Stock'
    END AS stock_status,
    CASE
        WHEN i.Units_Sold > 0 THEN ROUND(i.inventory_level_fixed / i.Units_Sold, 1)
        ELSE 999
    END AS days_of_supply
FROM
    `carbon-watch-456400-u1.supply_chain_project.supply_info_cleaned` i
LEFT JOIN
    `carbon-watch-456400-u1.supply_chain_project.abc_analysis_result` abc ON i.sku_id = abc.sku_id;