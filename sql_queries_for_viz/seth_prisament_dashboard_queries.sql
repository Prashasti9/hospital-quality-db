-- dashboard_queries_seth_prisament.sql
-- DSAI-691 Group 6: U.S. Hospital Quality & Cost
-- Phase-3: SQL behind the Metabase dashboard.
--
-- Story: Does spending more actually result in better healthcare?
--
-- Tables (one row per hospital per measure in the fact tables):
--   dim_hospital(facility_id, state, hospital_ownership, overall_rating, ...)
--   dim_measure(measure_id, measure_name, measure_domain)
--   fact_spending(facility_id, measure_id, mspb_ratio, ...)
--   fact_patient_survey(facility_id, measure_id, star_rating, ...)
--   fact_infections(facility_id, measure_id, compared_to_national, score, ...)
--
-- mspb_ratio: 1.0 = national average spending (higher = more expensive).
-- star_rating: 1-5, higher = better.
-- score (mortality): risk-adjusted 30-day death rate, % of patients, lower = better.
-- ====================================================================


-- Viz 1: Average rating state
-- Chart: Map or bar
SELECT state,
       COUNT(*)                      AS hospitals,
       ROUND(AVG(overall_rating), 2) AS avg_rating
FROM dim_hospital
GROUP BY state
HAVING COUNT(*) >= 5
ORDER BY avg_rating DESC NULLS LAST;


-- Viz 2: Average spending by state
-- Chart: Map or bar
SELECT h.state,
       COUNT(*)                     AS hospitals,
       ROUND(AVG(f.mspb_ratio), 3)  AS avg_spend_ratio
FROM fact_spending f
JOIN dim_hospital h ON h.facility_id = f.facility_id
WHERE f.mspb_ratio IS NOT NULL
GROUP BY h.state
HAVING COUNT(*) >= 5
ORDER BY avg_spend_ratio DESC;


-- Viz 3: Average star rating by spending quartile
-- Chart: Bar 
WITH per_hospital AS (
    SELECT s.facility_id,
           AVG(f.mspb_ratio)  AS spend_ratio,
           AVG(s.star_rating) AS star
    FROM fact_spending f
    JOIN fact_patient_survey s ON s.facility_id = f.facility_id
    WHERE f.mspb_ratio IS NOT NULL AND s.star_rating IS NOT NULL
    GROUP BY s.facility_id
),
quartiles AS (
    SELECT spend_ratio, star,
           NTILE(4) OVER (ORDER BY spend_ratio) AS spend_quartile
    FROM per_hospital
)
SELECT spend_quartile,
       COUNT(*)                   AS hospitals,
       ROUND(AVG(spend_ratio), 3) AS avg_spend_ratio,
       ROUND(AVG(star), 2)        AS avg_star
FROM quartiles
GROUP BY spend_quartile
ORDER BY spend_quartile;


-- Viz 4: Average mortality by spending quartile
-- Chart: Bar
WITH mortality AS (
    SELECT f.facility_id, AVG(f.score) AS death_rate
    FROM fact_complications_deaths f
    JOIN dim_measure m ON m.measure_id = f.measure_id
    WHERE f.score IS NOT NULL
      AND m.measure_name ILIKE '%death%'
    GROUP BY f.facility_id
),
spend AS (
    SELECT facility_id, AVG(mspb_ratio) AS spend_ratio
    FROM fact_spending
    WHERE mspb_ratio IS NOT NULL
    GROUP BY facility_id
),
combined AS (
    SELECT s.facility_id, s.spend_ratio, mo.death_rate,
           NTILE(4) OVER (ORDER BY s.spend_ratio) AS spend_quartile
    FROM spend s
    JOIN mortality mo ON mo.facility_id = s.facility_id
)
SELECT spend_quartile,
       COUNT(*)                   AS hospitals,
       ROUND(AVG(spend_ratio), 3) AS avg_spend_ratio,
       ROUND(AVG(death_rate), 2)  AS avg_death_rate
FROM combined
GROUP BY spend_quartile
ORDER BY spend_quartile;