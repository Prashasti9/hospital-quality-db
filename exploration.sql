-- exploration.sql
-- DSAI-691 Group 6: U.S. Hospital Quality & Cost
--
-- Exploratory queries on the hospital_quality database.
-- Run create_and_load.sql first.
--
-- How to run (pgAdmin): open the Query Tool on hospital_quality,
-- highlight one query and press F5 to see its result.

-- 1. Rows per table
SELECT 'dim_hospital' AS table_name, COUNT(*) AS row_count FROM dim_hospital
UNION ALL SELECT 'dim_measure', COUNT(*) FROM dim_measure
UNION ALL SELECT 'dim_period', COUNT(*) FROM dim_period
UNION ALL SELECT 'fact_complications_deaths', COUNT(*) FROM fact_complications_deaths
UNION ALL SELECT 'fact_infections', COUNT(*) FROM fact_infections
UNION ALL SELECT 'fact_unplanned_visits', COUNT(*) FROM fact_unplanned_visits
UNION ALL SELECT 'fact_patient_survey', COUNT(*) FROM fact_patient_survey
UNION ALL SELECT 'fact_spending', COUNT(*) FROM fact_spending;

-- 2. Measures per domain
SELECT measure_domain, COUNT(*) AS measures
FROM dim_measure
GROUP BY measure_domain
ORDER BY measures DESC;

-- 3. Hospitals by type and ownership
SELECT hospital_type, hospital_ownership,
       COUNT(*)                                           AS hospitals,
       ROUND(100.0 * COUNT(overall_rating) / COUNT(*), 1) AS pct_rated,
       ROUND(AVG(overall_rating), 2)                      AS avg_star_rating
FROM dim_hospital
GROUP BY hospital_type, hospital_ownership
ORDER BY hospitals DESC;

-- 4. Overall star rating distribution
SELECT overall_rating, COUNT(*) AS hospitals
FROM dim_hospital
GROUP BY overall_rating
ORDER BY overall_rating;

-- 5. Spending ratio summary (1.00 = national median)
SELECT COUNT(mspb_ratio)         AS hospitals_with_score,
       MIN(mspb_ratio)           AS min_ratio,
       MAX(mspb_ratio)           AS max_ratio,
       ROUND(AVG(mspb_ratio), 3) AS avg_ratio
FROM fact_spending;

-- 6. Spending ratio by star rating
SELECT h.overall_rating,
       COUNT(*)                    AS hospitals,
       ROUND(AVG(s.mspb_ratio), 3) AS avg_spending_ratio
FROM fact_spending s
JOIN dim_hospital h ON h.facility_id = s.facility_id
WHERE h.overall_rating IS NOT NULL AND s.mspb_ratio IS NOT NULL
GROUP BY h.overall_rating
ORDER BY h.overall_rating;

-- 7. Patient survey stars by spending level
SELECT CASE WHEN s.mspb_ratio < 0.95 THEN '1. Low (below 0.95)'
            WHEN s.mspb_ratio <= 1.05 THEN '2. Average (0.95 to 1.05)'
            ELSE '3. High (above 1.05)' END AS spending_level,
       COUNT(ps.star_rating)          AS hospitals,
       ROUND(AVG(ps.star_rating), 2)  AS avg_patient_stars
FROM fact_spending s
JOIN fact_patient_survey ps ON ps.facility_id = s.facility_id
WHERE ps.measure_id = 'H_STAR_RATING'
  AND s.mspb_ratio IS NOT NULL
  AND ps.star_rating IS NOT NULL
GROUP BY spending_level
ORDER BY spending_level;

-- 8. Mortality results worse than national, by ownership
SELECT h.hospital_ownership,
       COUNT(f.compared_to_national) AS rated_results,
       SUM(CASE WHEN f.compared_to_national LIKE 'Worse%' THEN 1 ELSE 0 END) AS worse_results,
       ROUND(100.0 * SUM(CASE WHEN f.compared_to_national LIKE 'Worse%' THEN 1 ELSE 0 END)
             / COUNT(f.compared_to_national), 2) AS pct_worse
FROM fact_complications_deaths f
JOIN dim_hospital h ON h.facility_id = f.facility_id
WHERE f.measure_id LIKE 'MORT%'
  AND f.compared_to_national IS NOT NULL
GROUP BY h.hospital_ownership
ORDER BY pct_worse DESC;

-- 9. Average infection ratio (SIR) by measure (1.0 = national benchmark)
SELECT m.measure_id, m.measure_name,
       COUNT(f.score)         AS hospitals_reporting,
       ROUND(AVG(f.score), 3) AS avg_sir
FROM fact_infections f
JOIN dim_measure m ON m.measure_id = f.measure_id
WHERE f.measure_id LIKE '%SIR'
GROUP BY m.measure_id, m.measure_name
ORDER BY m.measure_id;

-- 10. Spending and star rating by state
SELECT h.state,
       COUNT(s.mspb_ratio)             AS hospitals_with_spending,
       ROUND(AVG(s.mspb_ratio), 3)     AS avg_spending_ratio,
       ROUND(AVG(h.overall_rating), 2) AS avg_star_rating
FROM dim_hospital h
LEFT JOIN fact_spending s ON s.facility_id = h.facility_id
GROUP BY h.state
HAVING COUNT(s.mspb_ratio) >= 10
ORDER BY avg_spending_ratio DESC;

-- 11. Top 10 states by heart failure readmission rate
SELECT h.state,
       COUNT(f.score)         AS hospitals_reporting,
       ROUND(AVG(f.score), 2) AS avg_hf_readmission_rate_pct
FROM fact_unplanned_visits f
JOIN dim_hospital h ON h.facility_id = f.facility_id
WHERE f.measure_id = 'READM_30_HF'
GROUP BY h.state
HAVING COUNT(f.score) >= 5
ORDER BY avg_hf_readmission_rate_pct DESC
LIMIT 10;

-- 12. Measurement periods by domain
SELECT m.measure_domain, p.start_date, p.end_date, COUNT(*) AS results
FROM (SELECT measure_id, period_id FROM fact_complications_deaths
      UNION ALL SELECT measure_id, period_id FROM fact_infections
      UNION ALL SELECT measure_id, period_id FROM fact_unplanned_visits
      UNION ALL SELECT measure_id, period_id FROM fact_patient_survey
      UNION ALL SELECT measure_id, period_id FROM fact_spending) f
JOIN dim_measure m ON m.measure_id = f.measure_id
LEFT JOIN dim_period p ON p.period_id = f.period_id
GROUP BY m.measure_domain, p.start_date, p.end_date
ORDER BY m.measure_domain, p.start_date;

-- 13. Spot check one hospital (compare with medicare.gov/care-compare)
SELECT h.facility_id, h.facility_name, h.city_town, h.state,
       h.overall_rating, s.mspb_ratio, ps.star_rating AS patient_survey_stars
FROM dim_hospital h
LEFT JOIN fact_spending s        ON s.facility_id = h.facility_id
LEFT JOIN fact_patient_survey ps ON ps.facility_id = h.facility_id
                                AND ps.measure_id = 'H_STAR_RATING'
WHERE h.facility_id = '010001';
