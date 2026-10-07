-- OLIST DATA QUALITY AND RECONCILIATION
-- How many rows does the customers table contain?

SELECT
	'customers' AS table_name,
	COUNT(*) AS row_count
FROM olist.customers
-- How many rows does each core Olist table contain?
UNION ALL
SELECT
	'orders' AS table_name,
	COUNT(*) AS row_count
FROM olist.orders
UNION ALL
SELECT
	'products' AS table_name,
	COUNT(*) AS row_count
FROM olist.products
UNION ALL
SELECT
	'order_items' AS table_name,
	COUNT(*) AS row_count
FROM olist.order_items
UNION ALL
SELECT
	'category_translation' AS table_name,
	COUNT(*) AS row_count
FROM olist.category_translation;




-- How many customers are missing a unique customer identifier?
SELECT
	COUNT(*) AS total_rows,
	COUNT(*) FILTER (WHERE c.customer_unique_id IS NULL) AS null_customer_unique_id
FROM olist.customers AS c;




-- Which CUSTOMER fields contain missing values?
SELECT
	COUNT(*) AS total_rows,
	COUNT(*) FILTER (WHERE c.customer_unique_id IS NULL) AS null_customer_unique_id,
	COUNT(*) FILTER (WHERE c.customer_id IS NULL) AS null_customer_id,
	COUNT(*) FILTER (WHERE c.customer_zip_code_prefix IS NULL) AS null_customer_zip_code_prefix,
	COUNT(*) FILTER (WHERE c.customer_city IS NULL) AS null_customer_city,
	COUNT(*) FILTER (WHERE c.customer_state IS NULL) AS null_customer_state
FROM olist.customers AS c;




-- Which critical ORDERS fields contain missing values?

SELECT
	COUNT(*) AS total_rows,
	COUNT(*) FILTER (WHERE o.order_id IS NULL) AS null_order_id,
	COUNT(*) FILTER (WHERE o.customer_id IS NULL) AS null_customer_id,
	COUNT(*) FILTER (WHERE o.order_status IS NULL) AS null_order_status,
	COUNT(*) FILTER (WHERE o.order_purchase_timestamp IS NULL) AS null_order_purchase_timestamp,
	COUNT(*) FILTER (WHERE o.order_approved_at IS NULL) AS null_order_approved_at,
	COUNT(*) FILTER (WHERE o.order_delivered_carrier_date IS NULL) AS null_order_delivered_carrier_date,
	COUNT(*) FILTER (WHERE o.order_delivered_customer_date IS NULL) AS null_order_delivered_customer_date,
	COUNT(*) FILTER (WHERE o.order_estimated_delivery_date IS NULL) AS null_order_estimated_delivery_date
FROM olist.orders AS o;




-- Are any DELIVERED ORDERS missing required lifecycle timestamps?
SELECT
	COUNT(*) FILTER 
	(WHERE o.order_status = 'delivered' AND o.order_approved_at IS NULL) AS delivered_missing_approval,
	COUNT(*) FILTER
	(WHERE o.order_status = 'delivered' AND o.order_delivered_carrier_date IS NULL) AS delivered_missing_carrier_date,
	COUNT(*) FILTER
	(WHERE o.order_status = 'delivered' AND o.order_delivered_customer_date IS NULL) AS delivered_missing_customer_date,
	COUNT(*) FILTER 
	(WHERE o.order_status = 'delivered') AS delivered_order
FROM olist.orders AS o;




-- Do all DELIVERED ORDER have a CUSTOMER delivery timestamp?

SELECT
	'DQ-001: Delivered orders must have a delivery timestamp' AS test_name,
	COUNT(*) AS issue_count,
	CASE
		WHEN COUNT(*) = 0 THEN 'PASS'
		ELSE 'FAIL'
	END AS status
FROM olist.orders AS o
WHERE o.order_status = 'delivered' AND o.order_delivered_customer_date IS NULL;




-- Is customer_id unique in the customers table?

SELECT
	COUNT(*) AS total_rows,
	COUNT(DISTINCT c.customer_id) AS distinct_id,
	COUNT(*) - COUNT(DISTINCT c.customer_id) AS duplicate_customer_ids
FROM olist.customers AS c;


-- How many customer records represent repeat appearances of the same real customer?
SELECT
	COUNT(*) AS total_rows,
	COUNT(DISTINCT c.customer_unique_id) AS distinct_unique_customers,
	COUNT(*) - COUNT(DISTINCT c.customer_unique_id) AS repeated_customer_records
FROM olist.customers AS c;



-- What date range does the order purchase data cover?

SELECT
	MIN(o.order_purchase_timestamp) AS first_order,
	MAX(o.order_purchase_timestamp) AS last_order,
	MAX(o.order_purchase_timestamp) - MIN(o.order_purchase_timestamp) AS observed_period
FROM olist.orders AS o;



-- What date range does the shipping deadline data cover?
SELECT
	MIN(i.shipping_limit_date) AS first_shipping_date,
	MAX(i.shipping_limit_date) AS last_shipping_date,
	MAX(i.shipping_limit_date) - MIN(i.shipping_limit_date) AS observed_period
FROM olist.order_items AS i;





-- What is the total payment amount for each order?
SELECT
	order_id,
	SUM(payment_value) AS total_payment
FROM olist.order_payments
GROUP BY order_id;




-- What is the total item and freight amount for each order?

SELECT
	order_id,
	SUM(price + freight_value) AS total_amount
FROM olist.order_items
GROUP BY order_id;





-- Do total customer payments match item and freight totals for each order?

WITH customer_payment AS (
SELECT
	order_id,
	SUM(payment_value) AS total_payment
FROM olist.order_payments
GROUP BY order_id
),
items_total AS(
SELECT 
	order_id,
	SUM(price + freight_value) AS total_amount
FROM olist.order_items
GROUP BY order_id
)
SELECT 
	p.order_id,
	p.total_payment,
	i.total_amount
FROM customer_payment AS p
JOIN items_total AS i
	ON p.order_id = i.order_id;




-- What is the difference between the payment and item totals for each order?


WITH customer_payment AS (
SELECT
	order_id,
	SUM(payment_value) AS total_payment
FROM olist.order_payments
GROUP BY order_id
),
items_total AS(
SELECT 
	order_id,
	SUM(price + freight_value) AS total_amount
FROM olist.order_items
GROUP BY order_id
)
SELECT 
	p.order_id,
	p.total_payment,
	i.total_amount,
	p.total_payment - i.total_amount AS amount_difference
FROM customer_payment AS p
JOIN items_total AS i
	ON p.order_id = i.order_id;



-- How many orders have a payment difference greater than one cent?

WITH customer_payment AS (
SELECT
	order_id,
	SUM(payment_value) AS total_payment
FROM olist.order_payments
GROUP BY order_id
),
items_total AS(
SELECT 
	order_id,
	SUM(price + freight_value) AS total_amount
FROM olist.order_items
GROUP BY order_id
),
compared_amount AS(
SELECT 
	COALESCE(p.order_id, i.order_id) AS order_id,
	p.total_payment,
	i.total_amount,
	p.total_payment - i.total_amount AS amount_difference
FROM customer_payment AS p
FULL JOIN items_total AS i
	ON p.order_id = i.order_id
)
-- SELECT
-- 	COUNT(*) AS total_reconciliation_orders,
-- 	COUNT(*) FILTER (WHERE ABS(amount_difference)<=0.01) AS matched_orders,
-- 	COUNT(*) FILTER (WHERE ABS(amount_difference)>0.01) AS mismatched_orders,
-- 	COUNT(*) FILTER (WHERE total_payment IS NOT NULL AND total_amount IS NULL) AS missing_item_orders,
-- 	COUNT(*) FILTER (WHERE total_amount IS NOT NULL AND total_payment IS NULL) AS missing_payment_orders,
-- 	ROUND(MAX(ABS(amount_difference)),2) AS max_difference
-- FROM compared_amount;


-- SELECT
-- 	a.order_id,
-- 	a.total_payment,
-- 	a.total_amount,
-- 	o.order_status
-- FROM compared_amount AS a
-- JOIN olist.orders AS o
-- 	ON a.order_id = o.order_id
-- WHERE total_payment IS NULL AND total_amount IS NOT NULL;

-- Finding: One delivered order has item records totaling BRL 143.46 but no payment record.


-- Delivered orders with items must have a payment record
SELECT
   'DQ-001: Delivered orders with items must have a payment record' AS test_name,
    COUNT(*) AS issue_count,
	CASE
		WHEN COUNT(*) = 0 THEN 'PASS'
		ELSE 'FAIL'
	END AS status
FROM compared_amount AS a
JOIN olist.orders AS o
 	ON a.order_id = o.order_id 
WHERE o.order_status = 'delivered' 
AND total_payment IS NULL
AND total_amount IS NOT NULL 

UNION ALL

-- Payment totals must match item and freight totals within BRL 0.01.

SELECT
   'DQ-002: Payment must match item and freight total within BRL 0.01' AS test_name,
    COUNT(*) AS issue_count,
	CASE
		WHEN COUNT(*) = 0 THEN 'PASS'
		ELSE 'FAIL'
	END AS status
FROM compared_amount 
WHERE ABS(amount_difference) > 0.01

-- Do all payment records belong to an existing order?

UNION ALL

SELECT
    'DQ-003: All payment records must belong to an existing order' AS test_name,
    COUNT(*) AS issue_count,
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM olist.order_payments AS p
LEFT JOIN olist.orders AS o
	ON p.order_id = o.order_id
WHERE o.order_id IS NULL


-- Do all order item records belong to an existing order?

UNION ALL

SELECT
    'DQ-004: All order item records must belong to an existing order' AS test_name,
    COUNT(*) AS issue_count,
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM olist.order_items AS i
LEFT JOIN olist.orders AS o
	ON i.order_id = o.order_id
WHERE o.order_id IS NULL

-- Do all order item records reference an existing product?
 UNION ALL

 
SELECT
	'DQ-005: All order item records must reference an existing product' AS test_name,
	COUNT(*) AS issue_count,
	CASE
		WHEN COUNT(*) = 0 THEN 'PASS'
		ELSE 'FAIL'
	END AS status
FROM olist.order_items AS i
LEFT JOIN olist.products AS p
	ON i.product_id = p.product_id
WHERE p.product_id IS NULL

-- Are all item prices greater than zero?
UNION ALL
SELECT
	'DQ-006: All order item PRICE must be greater than zero' AS test_name,
	COUNT(*) AS issue_count,
	CASE 
		WHEN COUNT(*) = 0 THEN 'PASS'
		ELSE 'FAIL'
	END AS status
FROM olist.order_items
WHERE price<=0 OR price IS NULL;







                                    -- QA TEST

CREATE TEMP TABLE qa_orders AS
SELECT *
FROM olist.orders
LIMIT 100;

CREATE TEMP TABLE qa_order_payments AS
SELECT *
FROM olist.order_payments
WHERE order_id IN (
    SELECT order_id
    FROM qa_orders
);

CREATE TEMP TABLE qa_order_items AS
SELECT *
FROM olist.order_items
WHERE order_id IN (
    SELECT order_id
    FROM qa_orders
);

CREATE TEMP TABLE qa_products AS
SELECT *
FROM olist.products
WHERE product_id IN (
    SELECT product_id
    FROM qa_order_items
);


SELECT COUNT(*) FROM qa_orders;


INSERT INTO qa_orders (
    order_id,
    customer_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date
)
SELECT
    'QA_MISSING_PAYMENT',
    customer_id,
    'delivered',
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date
FROM qa_orders
WHERE order_status = 'delivered'
LIMIT 1;

INSERT INTO qa_order_items (
    order_id,
    order_item_id,
    product_id,
    seller_id,
    shipping_limit_date,
    price,
    freight_value
)
SELECT
    'QA_MISSING_PAYMENT',
    1,
    product_id,
    seller_id,
    shipping_limit_date,
    100.00,
    10.00
FROM qa_order_items
LIMIT 1;



SELECT
    'QA-001: Detect delivered order with items but no payment' AS test_name,
    COUNT(DISTINCT o.order_id) AS issue_count,
    CASE
        WHEN COUNT(DISTINCT o.order_id) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM qa_orders AS o
JOIN qa_order_items AS i
    ON o.order_id = i.order_id
LEFT JOIN qa_order_payments AS p
    ON o.order_id = p.order_id
WHERE o.order_status = 'delivered'
  AND p.order_id IS NULL;







































































