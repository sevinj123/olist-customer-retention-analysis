CREATE SCHEMA IF NOT EXISTS analytics;


CREATE TABLE analytics.dim_customer(
    customer_key       BIGINT   GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id        TEXT     NOT NULL UNIQUE,
    customer_unique_id TEXT,
    customer_city      TEXT,
    customer_state     CHAR(2)
);   

ALTER TABLE analytics.dim_customer
ADD COLUMN customer_zip_code_prefix INTEGER;


INSERT INTO analytics.dim_customer(
	customer_id,
    customer_unique_id,
	customer_zip_code_prefix,
    customer_city,
    customer_state
)
SELECT
	customer_id,
    customer_unique_id,
	customer_zip_code_prefix,
    customer_city,
    customer_state
FROM olist.customers;






CREATE TABLE analytics.dim_product (
    product_key                   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_category_name_english TEXT,
    product_name_lenght           NUMERIC,
    product_description_lenght    NUMERIC,
    product_photos_qty            NUMERIC,
    product_weight_g              NUMERIC,
    product_length_cm             NUMERIC,
    product_height_cm             NUMERIC,
    product_width_cm              NUMERIC
);


ALTER TABLE analytics.dim_product
ADD COLUMN product_id             TEXT NOT NULL UNIQUE,
ADD COLUMN product_category_name  TEXT;



INSERT INTO analytics.dim_product(
	product_id,
	product_category_name,
	product_category_name_english,
	product_name_lenght,
	product_description_lenght,
	product_photos_qty,
	product_weight_g,
	product_length_cm,
	product_height_cm,
	product_width_cm
)
SELECT
	p.product_id,
	p.product_category_name,
	ct.product_category_name_english,
	p.product_name_lenght,
	p.product_description_lenght,
	p.product_photos_qty,
	p.product_weight_g,
	p.product_length_cm,
	p.product_height_cm,
	p.product_width_cm
FROM olist.products AS p
LEFT JOIN olist.category_translation AS ct
	ON p.product_category_name = ct.product_category_name;




CREATE TABLE analytics.dim_seller (
    seller_key              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    seller_id               TEXT NOT NULL UNIQUE,
    seller_zip_code_prefix  INTEGER,
    seller_city             TEXT,
    seller_state            CHAR(2)
);



INSERT INTO analytics.dim_seller(
    seller_id,
    seller_zip_code_prefix,
    seller_city,
    seller_state
)
SELECT
    seller_id,
    seller_zip_code_prefix,
    seller_city,
    seller_state
FROM olist.sellers;




CREATE TABLE analytics.dim_date (
    date_key       INTEGER  PRIMARY KEY,
    full_date      DATE     NOT NULL UNIQUE,
    year_number    SMALLINT,
    quarter_number SMALLINT,
    month_number   SMALLINT,
    month_name     TEXT,
    day_of_month   SMALLINT,
    day_name       TEXT,
    is_weekend     BOOLEAN
);



-- Generate calendar dates from the Olist order period

WITH date_range AS (
    SELECT
        MIN(order_purchase_timestamp::DATE) AS first_date,
        MAX(order_purchase_timestamp::DATE) AS last_date
    FROM olist.orders
),
calendar AS (
    SELECT
        GENERATE_SERIES(
            first_date,
            last_date,
            INTERVAL '1 day'
        )::DATE AS full_date
    FROM date_range
)
INSERT INTO analytics.dim_date (
    date_key,
    full_date,
    year_number,
    quarter_number,
    month_number,
    month_name,
    day_of_month,
    day_name,
    is_weekend
)
SELECT
    TO_CHAR(full_date, 'YYYYMMDD')::INTEGER AS date_key,
    full_date,
    EXTRACT(YEAR FROM full_date)::SMALLINT AS year_number,
    EXTRACT(QUARTER FROM full_date)::SMALLINT AS quarter_number,
    EXTRACT(MONTH FROM full_date)::SMALLINT AS month_number,
    TRIM(TO_CHAR(full_date, 'Month')) AS month_name,
    EXTRACT(DAY FROM full_date)::SMALLINT AS day_of_month,
    TRIM(TO_CHAR(full_date, 'Day')) AS day_name,
    EXTRACT(ISODOW FROM full_date) IN (6, 7) AS is_weekend
FROM calendar
ORDER BY full_date;




CREATE TABLE analytics.fact_order_items (
    order_id TEXT NOT NULL,
    order_item_id INTEGER NOT NULL,
	product_key BIGINT NOT NULL
		REFERENCES analytics.dim_product(product_key),
	customer_key BIGINT NOT NULL
		REFERENCES analytics.dim_customer(customer_key),
	seller_key BIGINT NOT NULL
		REFERENCES analytics.dim_seller(seller_key),
	date_key INTEGER NOT NULL
		REFERENCES analytics.dim_date(date_key),
	quantity SMALLINT NOT NULL DEFAULT 1,
	price NUMERIC(12,2) NOT NULL,
	freight_value NUMERIC(12,2) NOT NULL,
	item_total NUMERIC(14,2) 
		GENERATED ALWAYS AS (price + freight_value) STORED,
	PRIMARY KEY (order_id, order_item_id)
);



INSERT INTO analytics.fact_order_items(
SELECT
	i.order_id,
	i.order_item_id,
	ap.product_key,
	ca.customer_key,
	sa.seller_key,
	da.date_key,
	1 AS quantity,
	i.price,
	i.freight_value
FROM olist.order_items AS i
JOIN olist.orders AS o
	ON i.order_id = o.order_id
JOIN analytics.dim_product AS ap
	ON i.product_id = ap.product_id
JOIN analytics.dim_customer AS ca
	ON o.customer_id = ca.customer_id
JOIN analytics.dim_seller AS sa
	ON i.seller_id = sa.seller_id
JOIN analytics.dim_date AS da
	ON o.order_purchase_timestamp::date = da.full_date
);



SELECT
    order_id,
    order_item_id,
    price,
    freight_value,
    item_total
FROM analytics.fact_order_items
LIMIT 10;



EXPLAIN ANALYZE
SELECT *
FROM analytics.fact_order_items
WHERE product_key = 27445;


CREATE INDEX idx_fact_order_items_product_key
ON analytics.fact_order_items(product_key);


EXPLAIN ANALYZE
SELECT *
FROM analytics.fact_order_items
WHERE product_key = 27445;




-- How many new customers were acquired each month?
WITH customer_first_order AS(
SELECT
    c.customer_unique_id,
    MIN(d.full_date) AS first_order_date
FROM analytics.fact_order_items AS f
JOIN analytics.dim_date AS d
    ON f.date_key = d.date_key
JOIN analytics.dim_customer AS c
    ON f.customer_key = c.customer_key
GROUP BY c.customer_unique_id
)
SELECT
	DATE_TRUNC('month', first_order_date) AS acquisition_month,
	COUNT(DISTINCT customer_unique_id) AS new_customer
FROM customer_first_order
GROUP BY acquisition_month
ORDER BY acquisition_month;




-- Which customer states have the highest late-delivery rate?

WITH customer_delivery_rate AS (
SELECT
	o.order_id,
	c.customer_state,
	o.order_delivered_customer_date AS actual_delivery_date,
	o.order_estimated_delivery_date AS estimated_delivery_date
FROM olist.orders AS o
JOIN olist.customers AS c
	ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
AND o.order_delivered_customer_date IS NOT NULL
AND o.order_estimated_delivery_date IS NOT NULL
),
delivered_late_order AS(
SELECT 
	COUNT(*) AS delivered_orders,
	customer_state,
	COUNT(*) FILTER (WHERE actual_delivery_date>estimated_delivery_date) AS late_orders
FROM customer_delivery_rate
GROUP BY customer_state
)
SELECT
	customer_state,
	delivered_orders,
    late_orders,
	ROUND(100.0*late_orders/delivered_orders,2) AS late_delivery_rate
FROM delivered_late_order
ORDER BY late_delivery_rate DESC;




-- How does the average review score differ between on-time and late deliveries?
WITH review_delivery AS (
SELECT
	o.order_id,
	r.review_score,
	o.order_delivered_customer_date AS actual_delivery_date,
	o.order_estimated_delivery_date AS estimated_delivery_date
FROM olist.orders AS o
JOIN olist.order_reviews AS r
	ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
AND o.order_delivered_customer_date IS NOT NULL
AND o.order_estimated_delivery_date IS NOT NULL
),
delivery_time AS (
SELECT
	rd.order_id,
	rd.review_score,
	rd.actual_delivery_date,
	rd.estimated_delivery_date,
	CASE
		WHEN actual_delivery_date > estimated_delivery_date THEN 'late_delivery'
		ELSE 'on_time'
	END AS delivery_status
FROM review_delivery AS rd
)
SELECT
	ROUND(AVG(review_score),2) AS avg_review_score,
	delivery_status,
	COUNT(review_score) AS review_count
FROM delivery_time
GROUP BY delivery_status;
-- Late deliveries are associated with substantially lower customer satisfaction.




-- Is the difference in review scores between on-time and late deliveries statistically meaningful?
WITH review_delivery AS (
SELECT
	o.order_id,
	r.review_score,
	o.order_delivered_customer_date AS actual_delivery_date,
	o.order_estimated_delivery_date AS estimated_delivery_date
FROM olist.orders AS o
JOIN olist.order_reviews AS r
	ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
AND o.order_delivered_customer_date IS NOT NULL
AND o.order_estimated_delivery_date IS NOT NULL
),
delivery_time AS (
SELECT
	rd.order_id,
	rd.review_score,
	rd.actual_delivery_date,
	rd.estimated_delivery_date,
	CASE
		WHEN actual_delivery_date > estimated_delivery_date THEN 'late_delivery'
		ELSE 'on_time'
	END AS delivery_status
FROM review_delivery AS rd
),
delivery_customer_status AS(
SELECT
	delivery_status,
	AVG(review_score) AS avg_review_score,
	COUNT(review_score) AS review_count,
	STDDEV_SAMP(review_score) AS review_score_stddev
FROM delivery_time
GROUP BY delivery_status
)
SELECT
	on_time.avg_review_score AS on_time_avg,
	late_time.avg_review_score AS late_time_avg,
	on_time.avg_review_score - late_time.avg_review_score AS mean_difference
FROM delivery_customer_status AS on_time
CROSS JOIN delivery_customer_status AS late_time
WHERE on_time.delivery_status = 'on_time'
	AND late_time.delivery_status = 'late_delivery';




-- Which payment types generate the highest revenue and order volume?
SELECT
	p.payment_type,
	SUM(p.payment_value) AS revenue,
	COUNT(DISTINCT p.order_id) AS order_volume
FROM olist.order_payments AS p
GROUP BY p.payment_type
ORDER BY revenue DESC;




-- Which customer states have the highest repeat purchase rate?
WITH customer_unique_state AS(
SELECT
	c.customer_state,
	c.customer_unique_id,
	COUNT(DISTINCT o.order_id) AS order_count
FROM olist.customers AS c
JOIN olist.orders AS o
	ON c.customer_id = o.customer_id
GROUP BY c.customer_state, c.customer_unique_id
),
repeat_state_customer AS(
SELECT
	cus.customer_state,
	COUNT(*) AS total_customer,
	COUNT(*) FILTER(WHERE order_count > 1) AS repeat_customers
FROM customer_unique_state AS cus
GROUP BY cus.customer_state
)
SELECT
	rsc.customer_state,
	rsc.total_customer,
	rsc.repeat_customers,
	ROUND(100.0 * repeat_customers/total_customer ,2) AS repeat_purchase_rate,
	DENSE_RANK() OVER (ORDER BY 100.0 * rsc.repeat_customers / rsc.total_customer DESC) AS repeat_rate_rank
FROM repeat_state_customer AS rsc
WHERE total_customer >= 500
ORDER BY repeat_purchase_rate DESC;




-- How does repeat purchase behavior differ by acquisition cohort?
WITH customer_cohort AS (
SELECT
	c.customer_unique_id,
	COUNT(DISTINCT o.order_id) AS order_count,
	DATE_TRUNC('month', MIN(o.order_purchase_timestamp::date)) AS cohort_month
FROM olist.customers AS c
JOIN olist.orders AS o
	ON c.customer_id = o.customer_id
GROUP BY c.customer_unique_id
),
total_repeat_customer AS (
SELECT
	cohort_month,
	COUNT(*) AS total_customer,
	COUNT(*) FILTER (WHERE order_count > 1) AS repeat_customers
FROM customer_cohort AS cc
GROUP BY cohort_month
)
SELECT
	cohort_month,
	total_customer,
	repeat_customers,
	ROUND(100.0*repeat_customers/total_customer,2) AS repeat_rate
FROM total_repeat_customer AS trc
WHERE total_customer >= 500
ORDER BY cohort_month;




-- VALIDATION
SELECT
	COUNT(*) AS null_customer_unique_id
FROM olist.customers
WHERE customer_unique_id IS NULL;



SELECT 
	COUNT(*) AS null_order_id
FROM olist.orders
WHERE order_id IS NULL;


-- Check duplicate order IDs
SELECT
	order_id,
	COUNT(*) AS dublicate_count
FROM olist.orders
GROUP BY order_id
HAVING COUNT(*) > 1;




SELECT
	COUNT(*) AS missing_delivery_dates
FROM olist.orders AS o
WHERE o.order_status = 'delivered'
  AND (o.order_delivered_customer_date IS NULL
  OR o.order_estimated_delivery_date IS NULL);





-- Validation 3: Check invalid review scores
SELECT
    COUNT(*) AS invalid_review_scores
FROM olist.order_reviews
WHERE review_score IS NULL
   OR review_score NOT BETWEEN 1 AND 5;




-- Validation 4: Check invalid payment values
SELECT
    COUNT(*) AS invalid_payment_values
FROM olist.order_payments
WHERE payment_value IS NULL
   OR payment_value < 0;




-- Validation 4: Check invalid payment values
SELECT
    COUNT(*) AS invalid_payment_values
FROM olist.order_payments
WHERE payment_value IS NULL
   OR payment_value < 0;



-- Validation 5: Check invalid repeat customer counts
WITH customer_unique_state AS(
SELECT
	c.customer_state,
	c.customer_unique_id,
	COUNT(DISTINCT o.order_id) AS order_count
FROM olist.customers AS c
JOIN olist.orders AS o
	ON c.customer_id = o.customer_id
GROUP BY c.customer_state, c.customer_unique_id
),
repeat_state_customer AS(
SELECT
	cus.customer_state,
	COUNT(*) AS total_customer,
	COUNT(*) FILTER(WHERE order_count > 1) AS repeat_customers
FROM customer_unique_state AS cus
GROUP BY cus.customer_state
)
SELECT
    COUNT(*) AS invalid_repeat_results
FROM repeat_state_customer
WHERE repeat_customers > total_customer
   OR repeat_customers < 0
   OR total_customer <= 0;




WITH customer_first_order AS(
SELECT
    c.customer_unique_id,
    MIN(d.full_date) AS first_order_date
FROM analytics.fact_order_items AS f
JOIN analytics.dim_date AS d
    ON f.date_key = d.date_key
JOIN analytics.dim_customer AS c
    ON f.customer_key = c.customer_key
GROUP BY c.customer_unique_id
)
SELECT
    COUNT(*) AS first_order_records,
    COUNT(DISTINCT customer_unique_id) AS distinct_customers
FROM customer_first_order;




   






























































































































