# Olist Customer Retention Analysis

SQL and Power BI analysis of customer acquisition, repeat purchasing, delivery performance, reviews, and payment behavior using the Olist Brazilian E-Commerce dataset.

## Dataset

**Source:** [Brazilian E-Commerce Public Dataset by Olist on Kaggle](https://www.kaggle.com/olistbr/brazilian-ecommerce/home)

The raw CSV files are not included in this repository. Download them from the source above and place them in the local `DATA/` directory.

## Dashboard

### Customer Retention

![Customer Retention dashboard](REPORT/images/customer-retention-dashboard.png)

### Delivery & Payments

![Delivery and Payments dashboard](REPORT/images/delivery-payments-dashboard.png)

## Key Findings

- Rio de Janeiro had the highest qualified repeat purchase rate at **3.40%**, followed by Mato Grosso at **3.31%** and Goiás at **3.28%**.
- São Paulo had the largest repeat-customer volume, with **1,296 repeat customers** and a **3.22%** repeat purchase rate.
- The overall late-delivery rate was **8.11%**.
- On-time deliveries received an average review score of **4.29**, compared with **2.57** for late deliveries.
- Credit cards generated the highest revenue and order volume.
- The analysis identified **95,420 acquired customers** during the observation period.

## Business Question

Which customer segments have higher repeat purchase rates, and how are retention outcomes associated with delivery performance, review scores, and payment behavior?

## Methodology

- Used `customer_unique_id` to identify customers across multiple orders.
- Defined a repeat customer as a customer with more than one distinct order.
- Calculated repeat purchase rate as repeat customers divided by total customers.
- Excluded states with fewer than 500 customers from the final state ranking to reduce small-sample distortion.
- Compared review scores for on-time and late deliveries.
- Validated customer identifiers, order uniqueness, repeat-customer counts, and first-order records.

## Tools

- PostgreSQL and pgAdmin 4
- Power BI Desktop
- Python, pandas, and Jupyter Notebook

## Repository Structure

```text
dashboard-data/   CSV extracts used by Power BI
notebooks/        SQL-to-pandas workflow
POWER_BI/         Power BI dashboard file
REPORT/           Case study, quality report, and dashboard images
SQL/              Analysis, data modeling, performance, and quality SQL
```

## Main Files

- [Customer retention SQL](SQL/olist-customer-retention-analysis.sql)
- [Data quality suite](SQL/data-quality-suite.sql)
- [Data modeling and performance SQL](SQL/data-modeling-performance.sql)
- [Power BI dashboard](POWER_BI/olist_customer_retention_dashboard.pbix)
- [Case study](REPORT/olist-customer-retention-case-study.md)

## Limitations

The dataset covers a limited observation period and does not include detailed marketing, acquisition-cost, carrier-event, or customer-service data. The findings describe associations and should not be interpreted as causal effects.
