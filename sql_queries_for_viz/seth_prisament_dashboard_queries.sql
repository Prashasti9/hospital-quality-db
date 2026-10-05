-- dashboard_queries_seth_prisament.sql
-- DSAI-691 Group 6: U.S. Hospital Quality & Cost
-- Phase-3: SQL behind the Metabase dashboard.
--
-- Story: Does spending more actually result in better healthcare?
-- Across every tile the answer leans "no": higher-spending hospitals and
-- states do not score better on CMS quality measures, and sometimes score
-- slightly worse.
--
-- Tables (one row per hospital per measure in the fact tables):
--   dim_hospital(facility_id, state, hospital_ownership, overall_rating, ...)
--   dim_measure(measure_id, measure_name, measure_domain)
--   fact_spending(facility_id, measure_id, mspb_ratio, ...)
--   fact_patient_survey(facility_id, measure_id, star_rating, ...)
--   fact_complications_deaths(facility_id, measure_id, score, ...)
--
-- mspb_ratio:     1.0 = national average spending (higher = more expensive).
-- star_rating:    HCAHPS patient-survey summary, 1-5, higher = better.
-- overall_rating: CMS composite star rating, 1-5, higher = better.
-- score (mort.):  risk-adjusted 30-day death rate, % of patients, lower = better.
-- ====================================================================


-- Title: "CMS Overall Star Rating by State"
SELECT state,
       COUNT(*)                      AS hospitals,
       ROUND(AVG(overall_rating), 2) AS avg_rating
FROM dim_hospital
GROUP BY state
HAVING COUNT(*) >= 5
ORDER BY avg_rating DESC NULLS LAST;

--   Title: "Medicare Spending by State" 
SELECT h.state                     AS state,
       ROUND(AVG(s.mspb_ratio), 4) AS avg_spending_ratio,
FROM dim_hospital h
JOIN fact_complications_deaths cd ON cd.facility_id = h.facility_id
JOIN fact_spending s              ON s.facility_id  = h.facility_id
WHERE cd.measure_id = 'MORT_30_HF'
  AND cd.score IS NOT NULL
  AND s.mspb_ratio IS NOT NULL
GROUP BY h.state
ORDER BY h.state;

--   Title: "30-Day Heart-Failure Mortality by State"
SELECT h.state                     AS state,
       ROUND(AVG(cd.score), 2)     AS avg_hf_mortality,
FROM dim_hospital h
JOIN fact_complications_deaths cd ON cd.facility_id = h.facility_id
JOIN fact_spending s              ON s.facility_id  = h.facility_id
WHERE cd.measure_id = 'MORT_30_HF'
  AND cd.score IS NOT NULL
  AND s.mspb_ratio IS NOT NULL
GROUP BY h.state
ORDER BY h.state;


-- Title: "Does Spending More Lower Mortality? (One Dot = One Hospital)"
SELECT h.facility_id,
       h.facility_name,
       s.mspb_ratio  AS spending_ratio,     -- X axis
       cd.score      AS mortality_rate      -- Y axis
FROM dim_hospital h
JOIN fact_spending s              ON s.facility_id = h.facility_id
JOIN fact_complications_deaths cd ON cd.facility_id = h.facility_id
WHERE cd.measure_id = 'MORT_30_HF'
  AND cd.score IS NOT NULL
  AND s.mspb_ratio IS NOT NULL
ORDER BY spending_ratio;


-- Title: "Higher-Rated Hospitals Spend Less per Patient"
SELECT ps.star_rating              AS patient_star_rating,
       ROUND(AVG(s.mspb_ratio), 4) AS avg_spending_ratio,
       COUNT(*)                    AS n_hospitals
FROM dim_hospital h
JOIN fact_spending s        ON s.facility_id  = h.facility_id
JOIN fact_patient_survey ps ON ps.facility_id = h.facility_id
WHERE ps.measure_id = 'H_STAR_RATING'
  AND ps.star_rating IS NOT NULL
  AND s.mspb_ratio IS NOT NULL
GROUP BY ps.star_rating
ORDER BY ps.star_rating;