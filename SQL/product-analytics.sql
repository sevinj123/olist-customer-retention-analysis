-- Olist E-commerce Product Analytics
-- Day 16: Funnel, Cohort, Retention and Delivery Analysis
-- Database: olist_analytics
-- Source: Olist Brazilian E-commerce Dataset

CREATE SCHEMA IF NOT EXISTS olist;

CREATE TABLE IF NOT EXISTS olist.customers (
    customer_id              TEXT     PRIMARY KEY,
    customer_unique_id       TEXT,
    customer_zip_code_prefix INTEGER,
    customer_city            TEXT,
    customer_state           CHAR(2)
);




SELECT *
FROM olist.customers
LIMIT 10;



SELECT COUNT(*) AS customer_count
FROM olist.customers;




-- Table 2: Orders
CREATE TABLE IF NOT EXISTS olist.orders (
    order_id                      TEXT       PRIMARY KEY,
    customer_id                   TEXT,
    order_status                  TEXT,
    order_purchase_timestamp      TIMESTAMP,
    order_approved_at             TIMESTAMP,
    order_delivered_carrier_date  TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP
);



SELECT
	COUNT(*) AS order_count,
	MIN(order_purchase_timestamp) AS first_order_date,
	MAX (order_purchase_timestamp) AS last_order_date
FROM olist.orders;






-- Table 3: Order Items
CREATE TABLE IF NOT EXISTS olist.order_items (
    order_id                             TEXT,
    order_item_id                        INTEGER,
    product_id                           TEXT,
    seller_id                            TEXT,
    shipping_limit_date                  TIMESTAMP,
    price                                NUMERIC(12,2),
    freight_value                        NUMERIC(12,2),
    PRIMARY KEY (order_id, order_item_id)
);




SELECT
	COUNT(*) AS order_item_count,
	ROUND(SUM(price),2) AS total_product_value,
	ROUND(SUM(freight_value),2) AS total_freight_value
FROM olist.order_items;





CREATE TABLE IF NOT EXISTS olist.products (
    product_id                 TEXT PRIMARY KEY,
    product_category_name      TEXT,
    product_name_lenght        NUMERIC,
    product_description_lenght NUMERIC,
    product_photos_qty         NUMERIC,
    product_weight_g           NUMERIC,
    product_length_cm          NUMERIC,
    product_height_cm          NUMERIC,
    product_width_cm           NUMERIC
);


CREATE TABLE IF NOT EXISTS olist.order_payments (
    order_id             TEXT,
    payment_sequential   INTEGER,
    payment_type         TEXT,
    payment_installments INTEGER,
    payment_value        NUMERIC(12,2),
    PRIMARY KEY (order_id, payment_sequential)
);






SELECT COUNT(*) AS product_count
FROM olist.products;





CREATE TABLE IF NOT EXISTS olist.category_translation (
    product_category_name         TEXT PRIMARY KEY,
    product_category_name_english TEXT
);



SELECT COUNT(*)
FROM olist.category_translation;



-- Business Question 1:
-- How many orders reached each stage of the order lifecycle?

WITH funnel_count AS (
SELECT
	COUNT(*) AS total_count,
	COUNT(*) FILTER(WHERE order_approved_at IS NOT NULL) AS approved_orders,
	COUNT(*) FILTER(WHERE order_delivered_carrier_date IS NOT NULL) AS shipped_orders,
	COUNT(*) FILTER(WHERE order_delivered_customer_date IS NOT NULL) AS delivered_orders	
FROM olist.orders
)
SELECT
	total_count,
	approved_orders,
	shipped_orders,
	delivered_orders,
	total_count - approved_orders AS approval_drop_off,
	approved_orders - shipped_orders AS shipping_drop_off,
	shipped_orders - delivered_orders AS delivered_drop_off,
	ROUND(approved_orders::NUMERIC/NULLIF(total_count,0) * 100, 2) AS approval_conversion_rate,
	ROUND(shipped_orders::NUMERIC/NULLIF(approved_orders,0) * 100, 2) AS shipping_conversion_rate,
	ROUND(delivered_orders::NUMERIC/NULLIF(shipped_orders,0) * 100, 2) AS delivered_conversion_rate
FROM funnel_count;
-- Insight:
-- The largest order drop-off occurred between approval and shipping,
-- where 1,623 approved orders did not progress to the shipping stage.
-- Despite this, all stage-to-stage conversion rates remained above 98%.







WITH customer_orders AS(
SELECT
	c.customer_unique_id,
	COUNT(DISTINCT o.order_id) AS order_count
FROM olist.customers AS c
JOIN olist.orders AS o
	ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_unique_id
ORDER BY order_count DESC
)
SELECT
	COUNT(*) AS purchasing_customers,
	COUNT(*) FILTER (WHERE order_count >1) AS repeat_customers
FROM customer_orders;





"What percentage of all customers who made a purchase made a repeat purchase?"


WITH customer_orders AS(
SELECT
	c.customer_unique_id,
	COUNT(DISTINCT o.order_id) AS order_count
FROM olist.customers AS c
JOIN olist.orders AS o
	ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_unique_id
)
SELECT
	COUNT(*) AS purchasing_customers,
	COUNT(*) FILTER (WHERE order_count >1) AS repeat_customers,
	ROUND(COUNT(*) FILTER (WHERE order_count >1):: NUMERIC/NULLIF(COUNT(*),0)*100,2) AS repeat_purchase_rate
FROM customer_orders;

-- Insight:
-- Only 3.00% of customers with delivered orders made more than one purchase.
-- This indicates a low repeat purchase rate and a potential opportunity
-- to improve customer retention.








-- DELIVERY_TIME

SELECT
    o.order_id,
	o.order_purchase_timestamp,
	o.order_delivered_customer_date,
	o.order_delivered_customer_date - o.order_purchase_timestamp AS delivery_time
FROM olist.orders AS o
WHERE order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
ORDER BY delivery_time DESC;











-- Business Question 4:
-- How well do monthly customer cohorts retain over the first six months?

-- Step 1: Create the delivered customer order base.

WITH first_purchase AS(
SELECT
    c.customer_unique_id,
	DATE_TRUNC('month', MIN(o.order_purchase_timestamp)) AS acquisition_month
FROM olist.customers AS c
JOIN olist.orders AS o
    ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_unique_id
)
SELECT
	c.customer_unique_id,
	fp.acquisition_month,
	DATE_TRUNC('month', o.order_purchase_timestamp) AS activity_month
FROM olist.customers AS c
JOIN olist.orders AS o
    ON c.customer_id = o.customer_id
JOIN first_purchase AS fp
	ON c.customer_unique_id = fp.customer_unique_id
WHERE o.order_status = 'delivered'
ORDER BY c.customer_unique_id, activity_month;











-- activity_month ilə acquisition_month arasında neçə ay olduğunu tapırıq.



WITH first_purchase AS(
SELECT
    c.customer_unique_id,
	DATE_TRUNC('month', MIN(o.order_purchase_timestamp)) AS acquisition_month
FROM olist.customers AS c
JOIN olist.orders AS o
    ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_unique_id
),
customer_activity AS(
SELECT
	c.customer_unique_id,
	fp.acquisition_month,
	DATE_TRUNC('month', o.order_purchase_timestamp) AS activity_month
FROM olist.customers AS c
JOIN olist.orders AS o
    ON c.customer_id = o.customer_id
JOIN first_purchase AS fp
	ON c.customer_unique_id = fp.customer_unique_id
WHERE o.order_status = 'delivered'
),
-- Calculate how many months passed between acquisition and customer activity.
cohort_date AS(
SELECT
	customer_unique_id,
	acquisition_month,
	activity_month,
	(
	EXTRACT (YEAR FROM AGE(activity_month,acquisition_month))*12
	+
	EXTRACT (MONTH FROM AGE(activity_month,acquisition_month))
	)::INTEGER AS month_number
FROM customer_activity
),
-- Count unique active customers in months 0–6.
cohort_counts AS(
SELECT
	acquisition_month,
	month_number,
	COUNT(DISTINCT customer_unique_id) AS active_customers
FROM cohort_date
WHERE month_number BETWEEN 0 AND 6
GROUP BY acquisition_month, month_number
),
-- Store the fixed month 0 denominator for every cohort.
cohort_sizes AS(
SELECT
	acquisition_month,
	active_customers AS cohort_size
FROM cohort_counts
WHERE month_number = 0
),
-- What percentage of each original cohort returned in months 0–6?
cohort_return AS(
SELECT
	cc.acquisition_month,
	cc.month_number,
	cs.cohort_size,
	cc.active_customers,
	ROUND(cc.active_customers::NUMERIC/NULLIF(cs.cohort_size,0)*100,2) AS retention_rate
FROM cohort_sizes AS cs
JOIN cohort_counts AS cc
	ON cc.acquisition_month = cs.acquisition_month
)

-- How can we present the 0–6 month retention rates as a cohort matrix?

SELECT
	acquisition_month,
	cohort_size,
	MAX(retention_rate) FILTER (WHERE month_number = 0) AS month_0,
	MAX(retention_rate) FILTER (WHERE month_number = 1) AS month_1,
	MAX(retention_rate) FILTER (WHERE month_number = 2) AS month_2,
	MAX(retention_rate) FILTER (WHERE month_number = 3) AS month_3,
	MAX(retention_rate) FILTER (WHERE month_number = 4) AS month_4,
	MAX(retention_rate) FILTER (WHERE month_number = 5) AS month_5,
	MAX(retention_rate) FILTER (WHERE month_number = 6) AS month_6
FROM cohort_return
GROUP BY acquisition_month, cohort_size
ORDER BY acquisition_month;

























































































