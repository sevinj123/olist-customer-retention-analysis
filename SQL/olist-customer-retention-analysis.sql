/*
OLIST CUSTOMER RETENTION ANALYSIS

Main business question:
Which customer segments have higher repeat purchase rates?

Repeat customer definition:
A customer who has placed more than one distinct order.

Customer identifier:
customer_unique_id

Reason:
The same customer may have a different customer_id for each order.
customer_unique_id identifies the same person across multiple orders.

Primary metric:
Repeat purchase rate = repeat customers / total customers * 100

Primary segment:
Customer state, with a minimum sample size of 500 customers.

Supporting analysis:
Monthly customer acquisition, late-delivery rate by state,
review score by delivery status, and revenue and order volume by payment type.


Dataset source:
Olist Brazilian E-Commerce Public Dataset from Kaggle.

Database sources:
- analytics.fact_order_items
- analytics.dim_date
- analytics.dim_customer
- olist.orders
- olist.customers
- olist.order_reviews
- olist.order_payments



Validation rules:
- customer_unique_id and order_id must not be null.
- Repeat purchase rate must be between 0 and 100.
- Repeat customers must not exceed total customers.
- Actual and estimated delivery dates must exist for delivery comparisons.
- Review scores must be between 1 and 5.
- Payment values must not be negative.


Limitations:
- The dataset covers a limited historical period, so recent customers had less time to make another purchase.
- The analysis shows associations and does not prove that delivery delays cause lower review scores or repeat behavior.
- States with fewer than 500 customers are excluded from the final repeat-rate ranking.
- Review results include only orders with available review records.
- A single order may contain multiple payment records or payment methods.
- Older acquisition cohorts had more time to make repeat purchases, while newer cohorts had shorter observation periods.


Repeat purchase rates varied across acquisition cohorts. Only cohorts with at least 500 customers
were included to reduce the effect of small samples.
*/






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


