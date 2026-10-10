-- ============================================================================
-- DSAI-691 | Group 6 | Task 3: Metabase Dashboard Queries
-- U.S. Hospital Quality & Cost
--
-- STORY: Does spending more actually result in better healthcare?
--
-- STORYLINE
--   Section 1  Headline             Do higher-spending hospitals earn higher
--                                   quality ratings?
--   Section 2  Distributions        How are spending and each outcome spread
--                                   across hospitals?
--   Section 3  Clinical outcomes    Does extra spending reduce readmissions,
--                                   infections, or deaths?
--   Section 4  Patient experience   Where does the star-rating gap come from?
--   Section 5  Ownership            Who runs the hospitals, and what do they
--                                   cost?
--   Section 6  Geography            Which states spend the most, and why?
--
-- QUERY INDEX
--   Section 1: Headline
--     1.1  Star ratings and key outcomes change across spending quartile
--     1.2  Share of top-rated hospitals by spending tier
--   Section 2: Distributions
--     2.1  How is hospital spending distributed?
--     2.2  How are CMS overall and patient-survey star ratings distributed?
--     2.3  How are heart-failure readmission and death rates distributed?
--     2.4  How are infection ratios distributed?
--     2.5  How much do spending and each outcome vary from hospital to
--          hospital?
--     2.6  Heart-failure readmission rate variance within spending quartile
--     2.7  How much do spending and star ratings vary within each state?
--   Section 3: Clinical Outcomes
--     3.1  Hospital spending vs heart-failure readmission rates
--     3.2  Hospital spending vs heart-failure death rates
--     3.3  Infection ratios across spending quartiles for each infection type
--     3.4  Average infection ratio vs spending
--     3.5  Are higher-spending hospitals more often better than the national
--          rate on deaths and complications?
--   Section 4: Patient Experience
--     4.1  Hospital patient-survey ratings vs spending
--     4.2  Which survey topics drive the star rating gap across hospitals?
--     4.3  Would patients at higher-spending hospitals definitely recommend
--          them?
--   Section 5: Ownership
--     5.1  How do star ratings and spending differ by ownership type?
--     5.2  Which ownership types deliver high quality at low cost?
--     5.3  Do the ownership differences hold in every region of the country?
--   Section 6: Geography
--     6.1  Which states spend the most, and do they get better ratings?
--     6.2  How do states compare on CMS star ratings?
--     6.3  Do higher-spending states have lower heart-failure death rates?
--     6.4  Do states with more for-profit hospitals spend more?
--
-- TABLES (fact tables hold one row per hospital per measure)
--   dim_hospital(facility_id, facility_name, city_town, county_parish, zip_code,
--                state, hospital_type, hospital_ownership, overall_rating)
--   dim_measure(measure_id, measure_name, measure_domain)
--   fact_spending(facility_id, measure_id, mspb_ratio)
--   fact_patient_survey(facility_id, measure_id, star_rating, linear_mean_value,
--                       answer_percent, completed_surveys)
--   fact_infections(facility_id, measure_id, score)
--   fact_unplanned_visits(facility_id, measure_id, score, denominator)
--   fact_complications_deaths(facility_id, measure_id, score, compared_to_national)
--
-- KEY FIELDS
--   mspb_ratio      Medicare spending per patient episode. 1.0 = national median,
--                   higher = more expensive. Every query that uses fact_spending
--                   filters to measure_id = 'MSPB-1' so each hospital has one
--                   spending value.
--   overall_rating  CMS overall hospital star rating, 1-5 (higher = better).
--   star_rating     Patient-survey (HCAHPS) star rating, 1-5 (higher = better).
--   score           Readmissions / mortality: % of patients, lower = better.
--                   Infections: Standardized Infection Ratio (SIR), 1.0 = expected
--                   number of infections, lower = better.
--                   PSI_90: composite patient-safety index, lower = better.
--
-- HOW HOSPITALS ARE GROUPED BY SPENDING
--   Quartiles (NTILE(4))   Q1 = lowest-spending 25% ... Q4 = highest
--                          -> 1.1, 2.6, 3.3, 4.2
--   Spending tiers         Low < 0.95 | Average 0.95-1.05 | High > 1.05
--                          -> 1.2, 3.4, 3.5
--   Low-cost flag          mspb_ratio <= 1.0
--                          -> 5.2
-- ============================================================================


-- ============================================================================
-- SECTION 1: HEADLINE
-- Do higher-spending hospitals earn higher quality ratings?
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1.1  Star ratings and key outcomes change across spending quartile
-- Description:  Splits hospitals into four equal-sized spending groups and
--               compares average star rating, heart-failure readmission and
--               death rates, and patient-safety index (PSI-90) across them.
-- Metabase:     Combo chart. X = spending_quartile, Bars = avg_star_rating,
--               Line = avg_hf_readmission_pct (right axis). avg_hf_death_pct
--               and avg_psi_90 can be added or swapped in.
-- ----------------------------------------------------------------------------
WITH hospital_metrics AS (
    SELECT h.facility_id,
           h.overall_rating,
           s.mspb_ratio,
           r.score  AS hf_readmission_pct,
           d.score  AS hf_death_pct,
           p.score  AS psi_90
    FROM dim_hospital h
    JOIN fact_spending s
         ON s.facility_id = h.facility_id AND s.measure_id = 'MSPB-1'
    LEFT JOIN fact_unplanned_visits r
         ON r.facility_id = h.facility_id AND r.measure_id = 'READM_30_HF'
    LEFT JOIN fact_complications_deaths d
         ON d.facility_id = h.facility_id AND d.measure_id = 'MORT_30_HF'
    LEFT JOIN fact_complications_deaths p
         ON p.facility_id = h.facility_id AND p.measure_id = 'PSI_90'
    WHERE s.mspb_ratio IS NOT NULL
),
quartiles AS (
    SELECT *, NTILE(4) OVER (ORDER BY mspb_ratio) AS quartile
    FROM hospital_metrics
)
SELECT 'Q' || quartile || CASE quartile WHEN 1 THEN ' (lowest spend)'
                                        WHEN 4 THEN ' (highest spend)'
                                        ELSE '' END      AS spending_quartile,
       COUNT(*)                                          AS hospitals,
       MIN(mspb_ratio)                                   AS min_mspb,
       MAX(mspb_ratio)                                   AS max_mspb,
       ROUND(AVG(overall_rating), 2)                     AS avg_star_rating,
       ROUND(AVG(hf_readmission_pct), 2)                 AS avg_hf_readmission_pct,
       ROUND(AVG(hf_death_pct), 2)                       AS avg_hf_death_pct,
       ROUND(AVG(psi_90), 3)                             AS avg_psi_90
FROM quartiles
GROUP BY quartile
ORDER BY quartile;


-- ----------------------------------------------------------------------------
-- 1.2  Share of top-rated hospitals by spending tier
-- Description:  Percent of rated hospitals in each spending tier (Low below
--               0.95, Average 0.95 to 1.05, High above 1.05) that earn 4 or 5
--               stars.
-- Metabase:     Bar chart. X = spending_level, Y = pct_top_rated.
-- ----------------------------------------------------------------------------
SELECT CASE WHEN s.mspb_ratio <  0.95 THEN '1. Low (below 0.95)'
            WHEN s.mspb_ratio <= 1.05 THEN '2. Average (0.95 to 1.05)'
            ELSE                           '3. High (above 1.05)'
       END                                                     AS spending_level,
       COUNT(h.overall_rating)                                 AS rated_hospitals,
       SUM(CASE WHEN h.overall_rating >= 4 THEN 1 ELSE 0 END)  AS top_rated,
       ROUND(100.0 * SUM(CASE WHEN h.overall_rating >= 4 THEN 1 ELSE 0 END)
             / COUNT(h.overall_rating), 1)                     AS pct_top_rated
FROM fact_spending s
JOIN dim_hospital h ON h.facility_id = s.facility_id
WHERE s.measure_id = 'MSPB-1'
  AND s.mspb_ratio IS NOT NULL
  AND h.overall_rating IS NOT NULL
GROUP BY spending_level
ORDER BY spending_level;



-- ============================================================================
-- SECTION 2: DISTRIBUTIONS
-- How are spending and each outcome spread across hospitals?
-- ===========================================================================


-- ----------------------------------------------------------------------------
-- 2.1  How is hospital spending distributed?
-- Description:  Number of hospitals in each 0.05-wide band of the Medicare
--               spending ratio (1.0 = national median). Bucket 0.90 covers
--               0.90 up to 0.95.
-- Metabase:     Bar chart. X = spending_bucket, Y = hospitals.
-- ----------------------------------------------------------------------------
SELECT ROUND((FLOOR(s.mspb_ratio / 0.05) * 0.05)::NUMERIC, 2) AS spending_bucket,
       COUNT(*)                                                AS hospitals,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)      AS pct_of_hospitals
FROM fact_spending s
WHERE s.measure_id = 'MSPB-1'
  AND s.mspb_ratio IS NOT NULL
GROUP BY spending_bucket
ORDER BY spending_bucket;


-- ----------------------------------------------------------------------------
-- 2.2  How are CMS overall and patient-survey star ratings distributed?
-- Description:  Percent of hospitals at each star level (1-5) for the CMS
--               overall rating and the patient-survey (HCAHPS) summary
--               rating. Percentages are within each rating type, since the
--               two ratings cover different numbers of hospitals.
-- Metabase:     Bar chart. X = stars, Y = pct_of_hospitals, Series breakout =
--               rating_type.
-- ----------------------------------------------------------------------------
SELECT 'CMS overall rating'                                  AS rating_type,
       overall_rating                                        AS stars,
       COUNT(*)                                              AS hospitals,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)    AS pct_of_hospitals
FROM dim_hospital
WHERE overall_rating IS NOT NULL
GROUP BY overall_rating
UNION ALL
SELECT 'Patient survey rating',
       star_rating,
       COUNT(*),
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)
FROM fact_patient_survey
WHERE measure_id = 'H_STAR_RATING'
  AND star_rating IS NOT NULL
GROUP BY star_rating
ORDER BY rating_type, stars;


-- ----------------------------------------------------------------------------
-- 2.3  How are heart-failure readmission and death rates distributed?
-- Description:  Share of hospitals in each 1-point band of the 30-day heart-
--               failure readmission rate and the 30-day heart-failure death
--               rate, on one chart. Bucket 21 covers 21.00% to 21.99%. Shares
--               are used because a different number of hospitals reports each
--               measure. Lower is better for both.
-- Metabase:     Line chart. X = rate_pct_bucket, Y = pct_of_hospitals, series = outcome.
-- ----------------------------------------------------------------------------
SELECT 'HF readmission'                                      AS outcome,
       FLOOR(r.score)::INT                                   AS rate_pct_bucket,
       COUNT(*)                                              AS hospitals,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)    AS pct_of_hospitals
FROM fact_unplanned_visits r
WHERE r.measure_id = 'READM_30_HF'
  AND r.score IS NOT NULL
GROUP BY rate_pct_bucket

UNION ALL

SELECT 'HF death'                                            AS outcome,
       FLOOR(d.score)::INT                                   AS rate_pct_bucket,
       COUNT(*)                                              AS hospitals,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)    AS pct_of_hospitals
FROM fact_complications_deaths d
WHERE d.measure_id = 'MORT_30_HF'
  AND d.score IS NOT NULL
GROUP BY rate_pct_bucket

ORDER BY outcome, rate_pct_bucket;


-- ----------------------------------------------------------------------------
-- 2.4  How are infection ratios distributed?
-- Description:  Count of hospital results in each Standardized Infection
--               Ratio (SIR) range across the six infection types; each result
--               is one hospital on one infection type. 1.0 = the expected
--               number of infections, lower is better.
-- Metabase:     Bar chart. X = sir_bucket, Y = hospital_results.
-- ----------------------------------------------------------------------------
SELECT CASE WHEN f.score = 0   THEN '1. 0 (no infections)'
            WHEN f.score < 0.5 THEN '2. Above 0 to 0.49'
            WHEN f.score < 1.0 THEN '3. 0.50 to 0.99'
            WHEN f.score < 1.5 THEN '4. 1.00 to 1.49'
            WHEN f.score < 2.0 THEN '5. 1.50 to 1.99'
            ELSE                    '6. 2.00 or higher'
       END                                                   AS sir_bucket,
       COUNT(*)                                              AS hospital_results,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)    AS pct_of_results
FROM fact_infections f
WHERE f.measure_id LIKE 'HAI\__\_SIR'
  AND f.score IS NOT NULL
GROUP BY sir_bucket
ORDER BY sir_bucket;


-- ----------------------------------------------------------------------------
-- 2.5  How much do spending and each outcome vary from hospital to hospital?
-- Description:  Mean, standard deviation, min, 10th percentile, median, 90th
--               percentile, and max for spending and each outcome. cv_pct
--               (standard deviation as a percent of the mean) puts them on
--               one scale. Each metric uses every hospital that reports it,
--               so the hospitals column differs by row.
-- Metabase:     Bar chart. X = metric, Y = cv_pct.
-- ----------------------------------------------------------------------------
WITH metrics AS (
    SELECT 'Medicare spending ratio (1.0 = national median)' AS metric,
           s.mspb_ratio::NUMERIC                             AS metric_value
    FROM fact_spending s
    WHERE s.measure_id = 'MSPB-1'
      AND s.mspb_ratio IS NOT NULL
    UNION ALL
    SELECT 'CMS overall star rating (1-5)',
           h.overall_rating::NUMERIC
    FROM dim_hospital h
    WHERE h.overall_rating IS NOT NULL
    UNION ALL
    SELECT 'Heart-failure 30-day readmission rate (%)',
           r.score::NUMERIC
    FROM fact_unplanned_visits r
    WHERE r.measure_id = 'READM_30_HF'
      AND r.score IS NOT NULL
    UNION ALL
    SELECT 'Heart-failure 30-day mortality rate (%)',
           d.score::NUMERIC
    FROM fact_complications_deaths d
    WHERE d.measure_id = 'MORT_30_HF'
      AND d.score IS NOT NULL
    UNION ALL
    SELECT 'Patient safety index (PSI-90)',
           p.score::NUMERIC
    FROM fact_complications_deaths p
    WHERE p.measure_id = 'PSI_90'
      AND p.score IS NOT NULL
)
SELECT metric,
       COUNT(*)                                                                    AS hospitals,
       ROUND(AVG(metric_value), 3)                                                 AS mean_value,
       ROUND(STDDEV(metric_value), 3)                                              AS std_dev,
       ROUND(100.0 * STDDEV(metric_value) / AVG(metric_value), 1)                  AS cv_pct,
       ROUND(MIN(metric_value), 3)                                                 AS min_value,
       ROUND((PERCENTILE_CONT(0.10) WITHIN GROUP (ORDER BY metric_value))::NUMERIC, 3) AS p10,
       ROUND((PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY metric_value))::NUMERIC, 3) AS median,
       ROUND((PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY metric_value))::NUMERIC, 3) AS p90,
       ROUND(MAX(metric_value), 3)                                                 AS max_value
FROM metrics
GROUP BY metric
ORDER BY cv_pct DESC;


-- ----------------------------------------------------------------------------
-- 2.6  Heart-failure readmission rate variance within spending quartile
-- Description:  The 10th percentile, median, and 90th percentile of the
--               heart-failure readmission rate in each spending quartile. A
--               wide band means hospitals that spend the same still get very
--               different results; a band that does not drop means more
--               spending does not lower readmissions.
-- Metabase:     Line chart. X = spending_quartile, Y = p10_pct, median_pct,
--               and p90_pct as three series.
-- ----------------------------------------------------------------------------
WITH quartiles AS (
    SELECT s.facility_id,
           NTILE(4) OVER (ORDER BY s.mspb_ratio) AS quartile
    FROM fact_spending s
    WHERE s.measure_id = 'MSPB-1'
      AND s.mspb_ratio IS NOT NULL
)
SELECT 'Q' || q.quartile                                                          AS spending_quartile,
       COUNT(r.score)                                                             AS hospitals,
       ROUND(MIN(r.score), 2)                                                     AS min_pct,
       ROUND((PERCENTILE_CONT(0.10) WITHIN GROUP (ORDER BY r.score))::NUMERIC, 2) AS p10_pct,
       ROUND((PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY r.score))::NUMERIC, 2) AS median_pct,
       ROUND((PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY r.score))::NUMERIC, 2) AS p90_pct,
       ROUND(MAX(r.score), 2)                                                     AS max_pct,
       ROUND(STDDEV(r.score), 2)                                                  AS std_dev_pct
FROM quartiles q
JOIN fact_unplanned_visits r
     ON r.facility_id = q.facility_id AND r.measure_id = 'READM_30_HF'
WHERE r.score IS NOT NULL
GROUP BY q.quartile
ORDER BY q.quartile;


-- ----------------------------------------------------------------------------
-- 2.7  How much do spending and star ratings vary within each state?
-- Description:  Spread of spending (min, max, sd_mspb) and star ratings
--               (sd_star_rating) among hospitals inside each state with 10+
--               hospitals, to compare variation within states to the
--               differences between state averages.
-- Metabase:     Table sorted by sd_mspb, or a Scatter with X = sd_mspb and Y
--               = sd_star_rating (hover shows the state).
-- ----------------------------------------------------------------------------
SELECT h.state,
       COUNT(*)                                     AS hospitals,
       ROUND(AVG(s.mspb_ratio), 3)                  AS avg_mspb,
       ROUND(MIN(s.mspb_ratio), 3)                  AS min_mspb,
       ROUND(MAX(s.mspb_ratio), 3)                  AS max_mspb,
       ROUND(STDDEV(s.mspb_ratio), 3)               AS sd_mspb,
       ROUND(AVG(h.overall_rating), 2)              AS avg_star_rating,
       ROUND(STDDEV(h.overall_rating), 2)           AS sd_star_rating
FROM dim_hospital h
JOIN fact_spending s
     ON s.facility_id = h.facility_id AND s.measure_id = 'MSPB-1'
WHERE s.mspb_ratio IS NOT NULL
GROUP BY h.state
HAVING COUNT(*) >= 10
ORDER BY sd_mspb DESC;



-- ============================================================================
-- SECTION 3: CLINICAL OUTCOMES
-- Does extra spending reduce readmissions, infections, or deaths?
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 3.1  Hospital spending vs heart-failure readmission rates
-- Description:  One point per hospital with 150+ heart-failure case
--               spend_percentile shows where each hospital ranks on spending.
-- Metabase:     Scatter. X = mspb_ratio, Y = hf_readmission_pct.
-- ----------------------------------------------------------------------------
SELECT h.facility_name,
       h.city_town,
       h.state,
       COALESCE(h.overall_rating::TEXT || ' stars', 'Not rated')  AS star_rating,
       s.mspb_ratio,
       r.score                                                   AS hf_readmission_pct,
       ROUND((100 * PERCENT_RANK() OVER (ORDER BY s.mspb_ratio))::NUMERIC, 1)
                                                                 AS spend_percentile
FROM dim_hospital h
JOIN fact_spending s
     ON s.facility_id = h.facility_id AND s.measure_id = 'MSPB-1'
JOIN fact_unplanned_visits r
     ON r.facility_id = h.facility_id AND r.measure_id = 'READM_30_HF'
WHERE s.mspb_ratio IS NOT NULL
  AND r.score IS NOT NULL
  AND r.denominator >= 150
ORDER BY s.mspb_ratio;


-- ----------------------------------------------------------------------------
-- 3.2  Hospital spending vs heart-failure death rates
-- Description:  One point per hospital: Medicare spending ratio vs. 30-day
--               heart-failure mortality rate. The mortality counterpart to
--               3.1.
-- Metabase:     Scatter. X = spending_ratio, Y = mortality_rate.
-- ----------------------------------------------------------------------------
SELECT h.facility_id,
       h.facility_name,
       s.mspb_ratio  AS spending_ratio,
       cd.score      AS mortality_rate
FROM dim_hospital h
JOIN fact_spending s
     ON s.facility_id = h.facility_id AND s.measure_id = 'MSPB-1'
JOIN fact_complications_deaths cd
     ON cd.facility_id = h.facility_id
WHERE cd.measure_id = 'MORT_30_HF'
  AND cd.score IS NOT NULL
  AND s.mspb_ratio IS NOT NULL
ORDER BY spending_ratio;


-- ----------------------------------------------------------------------------
-- 3.3  Infection ratios across spending quartiles for each infection type
-- Description:  Average Standardized Infection Ratio (SIR; 1.0 = expected
--               number of infections, lower is better) for each of the six
--               infection types, by spending quartile.
-- Metabase:     Line chart. X = spending_quartile, Y = avg_infection_ratio,
--               Series breakout = infection_type.
-- ----------------------------------------------------------------------------
WITH quartiles AS (
    SELECT h.facility_id,
           NTILE(4) OVER (ORDER BY s.mspb_ratio) AS quartile
    FROM dim_hospital h
    JOIN fact_spending s
         ON s.facility_id = h.facility_id AND s.measure_id = 'MSPB-1'
    WHERE s.mspb_ratio IS NOT NULL
)
SELECT 'Q' || q.quartile          AS spending_quartile,
       m.measure_name             AS infection_type,
       COUNT(*)                   AS hospitals,
       ROUND(AVG(f.score), 3)     AS avg_infection_ratio
FROM quartiles q
JOIN fact_infections f ON f.facility_id = q.facility_id
JOIN dim_measure m     ON m.measure_id  = f.measure_id
WHERE f.measure_id LIKE 'HAI\__\_SIR'
  AND f.score IS NOT NULL
GROUP BY q.quartile, m.measure_name
ORDER BY m.measure_name, q.quartile;


-- ----------------------------------------------------------------------------
-- 3.4  Average infection ratio vs spending
-- Description:  Each hospital's infection ratios averaged across infection
--               types, then averaged by spending tier. A one-bar-per-tier
--               summary of 3.3.
-- Metabase:     Bar chart. X = spending_level, Y = avg_infection_sir.
-- ----------------------------------------------------------------------------
WITH hosp_sir AS (
    SELECT f.facility_id, AVG(f.score) AS avg_sir
    FROM fact_infections f
    WHERE f.measure_id LIKE '%SIR'
      AND f.score IS NOT NULL
    GROUP BY f.facility_id
)
SELECT CASE WHEN s.mspb_ratio <  0.95 THEN '1. Low (below 0.95)'
            WHEN s.mspb_ratio <= 1.05 THEN '2. Average (0.95 to 1.05)'
            ELSE                           '3. High (above 1.05)'
       END                       AS spending_level,
       COUNT(*)                  AS hospitals,
       ROUND(AVG(hs.avg_sir), 3) AS avg_infection_sir
FROM fact_spending s
JOIN hosp_sir hs ON hs.facility_id = s.facility_id
WHERE s.measure_id = 'MSPB-1'
  AND s.mspb_ratio IS NOT NULL
GROUP BY spending_level
ORDER BY spending_level;


-- ----------------------------------------------------------------------------
-- 3.5  Are higher-spending hospitals more often better than the national rate
--      on deaths and complications?
-- Description:  Share of death and complication results that CMS rates better
--               than, or worse than, the national rate, by spending tier.
-- Metabase:     Line chart, two series. X = spending_level, Y = pct_better
--               and pct_worse.
-- ----------------------------------------------------------------------------
SELECT CASE WHEN s.mspb_ratio < 0.95  THEN '1. Low (below 0.95)'
            WHEN s.mspb_ratio <= 1.05 THEN '2. Average (0.95 to 1.05)'
            ELSE '3. High (above 1.05)' END AS spending_level,
       COUNT(*) AS rated_results,
       ROUND(100.0 * SUM(CASE WHEN cd.compared_to_national LIKE 'Better%' THEN 1 ELSE 0 END)
             / COUNT(*), 2) AS pct_better,
       ROUND(100.0 * SUM(CASE WHEN cd.compared_to_national LIKE 'Worse%' THEN 1 ELSE 0 END)
             / COUNT(*), 2) AS pct_worse
FROM fact_complications_deaths cd
JOIN fact_spending s
     ON s.facility_id = cd.facility_id AND s.measure_id = 'MSPB-1'
WHERE s.mspb_ratio IS NOT NULL
  AND (cd.compared_to_national LIKE 'Better%'
       OR cd.compared_to_national LIKE 'No Different%'
       OR cd.compared_to_national LIKE 'Worse%')
GROUP BY spending_level
ORDER BY spending_level;



-- ============================================================================
-- SECTION 4: PATIENT EXPERIENCE
-- Where does the star-rating gap come from?
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 4.1  Hospital patient-survey ratings vs spending
-- Description:  Average Medicare spending ratio for hospitals at each
--               patient-survey (HCAHPS) star rating, 1-5.
-- Metabase:     Line chart. X = patient_star_rating, Y = avg_spending_ratio.
-- ----------------------------------------------------------------------------
SELECT ps.star_rating              AS patient_star_rating,
       ROUND(AVG(s.mspb_ratio), 4) AS avg_spending_ratio,
       COUNT(*)                    AS n_hospitals
FROM dim_hospital h
JOIN fact_spending s
     ON s.facility_id = h.facility_id AND s.measure_id = 'MSPB-1'
JOIN fact_patient_survey ps
     ON ps.facility_id = h.facility_id
WHERE ps.measure_id = 'H_STAR_RATING'
  AND ps.star_rating IS NOT NULL
  AND s.mspb_ratio IS NOT NULL
GROUP BY ps.star_rating
ORDER BY ps.star_rating;


-- ----------------------------------------------------------------------------
-- 4.2  Which survey topics drive the star rating gap across hospitals?
-- Description:  Average patient-survey star rating by topic for the lowest-
--               vs. highest-spending quartile. star_gap = highest minus
--               lowest, so the most negative topics are where high spenders
--               fall furthest behind.
-- Metabase:     Row chart. X = survey_topic, Y = star_gap (sorted, most
--               negative first). Or a bar chart with Y = lowest_spend_stars
--               and highest_spend_stars.
-- ----------------------------------------------------------------------------
WITH quartiles AS (
    SELECT h.facility_id,
           NTILE(4) OVER (ORDER BY s.mspb_ratio) AS quartile
    FROM dim_hospital h
    JOIN fact_spending s
         ON s.facility_id = h.facility_id AND s.measure_id = 'MSPB-1'
    WHERE s.mspb_ratio IS NOT NULL
)
SELECT REPLACE(m.measure_name, ' - star rating', '')               AS survey_topic,
       ROUND(AVG(ps.star_rating) FILTER (WHERE q.quartile = 1), 2) AS lowest_spend_stars,
       ROUND(AVG(ps.star_rating) FILTER (WHERE q.quartile = 4), 2) AS highest_spend_stars,
       ROUND(AVG(ps.star_rating) FILTER (WHERE q.quartile = 4)
           - AVG(ps.star_rating) FILTER (WHERE q.quartile = 1), 2) AS star_gap,
       COUNT(DISTINCT ps.facility_id)                              AS hospitals
FROM quartiles q
JOIN fact_patient_survey ps ON ps.facility_id = q.facility_id
JOIN dim_measure m          ON m.measure_id   = ps.measure_id
WHERE ps.star_rating IS NOT NULL
  AND q.quartile IN (1, 4)
GROUP BY m.measure_name
HAVING COUNT(DISTINCT ps.facility_id) >= 100
ORDER BY star_gap;


-- ----------------------------------------------------------------------------
-- 4.3  Would patients at higher-spending hospitals definitely recommend them?
-- Description:  One point per hospital with 100+ completed surveys: Medicare
--               spending ratio vs. percent of patients who would definitely
--               recommend the hospital, colored by patient-survey star
--               rating.
-- Metabase:     Scatter. X = mspb_ratio, Y = pct_definitely_recommend, Series
--               breakout = patient_survey_stars.
-- ----------------------------------------------------------------------------
SELECT h.facility_id,
       h.facility_name,
       h.hospital_ownership,
       s.mspb_ratio,
       rec.answer_percent AS pct_definitely_recommend,
       star.star_rating   AS patient_survey_stars,
       rec.completed_surveys
FROM fact_spending s
JOIN dim_hospital h ON h.facility_id = s.facility_id
JOIN fact_patient_survey rec ON rec.facility_id = s.facility_id
                            AND rec.measure_id  = 'H_RECMND_DY'
LEFT JOIN fact_patient_survey star ON star.facility_id = s.facility_id
                                  AND star.measure_id  = 'H_STAR_RATING'
WHERE s.measure_id = 'MSPB-1'
  AND s.mspb_ratio IS NOT NULL
  AND rec.answer_percent IS NOT NULL
  AND rec.completed_surveys >= 100
ORDER BY s.mspb_ratio DESC, star.star_rating;



-- ============================================================================
-- SECTION 5: OWNERSHIP
-- Who runs the hospitals, and what do they cost?
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 5.1  How do star ratings and spending differ by ownership type?
-- Description:  Average CMS star rating and Medicare spending ratio for each
--               ownership type with 20+ acute care hospitals.
-- Metabase:     Combo chart (bar + line). X = hospital_ownership, Bars (left
--               axis) = avg_star_rating, Line (right axis) =
--               avg_spending_ratio.
-- ----------------------------------------------------------------------------
SELECT h.hospital_ownership,
       COUNT(*)                        AS hospitals,
       ROUND(AVG(h.overall_rating), 2) AS avg_star_rating,
       ROUND(AVG(s.mspb_ratio), 3)     AS avg_spending_ratio
FROM dim_hospital h
LEFT JOIN fact_spending s
       ON s.facility_id = h.facility_id AND s.measure_id = 'MSPB-1'
WHERE h.hospital_type = 'Acute Care Hospitals'
GROUP BY h.hospital_ownership
HAVING COUNT(*) >= 20
ORDER BY avg_star_rating DESC;


-- ----------------------------------------------------------------------------
-- 5.2  Which ownership types deliver high quality at low cost?
-- Description:  Each acute care hospital is placed in one of four groups by
--               star rating (4-5 = high quality) and spending ratio (1.0 or
--               below = low cost). Ownership types with 50+ hospitals.
-- Metabase:     Stacked bar (100%). X = hospital_ownership, Y = hospitals,
--               Series breakout = value_group.
-- ----------------------------------------------------------------------------
SELECT h.hospital_ownership,
       CASE WHEN h.overall_rating >= 4 AND s.mspb_ratio <= 1.0 THEN '1. High quality, low cost'
            WHEN h.overall_rating >= 4                          THEN '2. High quality, high cost'
            WHEN s.mspb_ratio <= 1.0                            THEN '3. Lower quality, low cost'
            ELSE '4. Lower quality, high cost' END AS value_group,
       COUNT(*) AS hospitals
FROM dim_hospital h
JOIN fact_spending s
     ON s.facility_id = h.facility_id AND s.measure_id = 'MSPB-1'
WHERE h.hospital_type = 'Acute Care Hospitals'
  AND h.overall_rating IS NOT NULL
  AND s.mspb_ratio IS NOT NULL
  AND h.hospital_ownership IN (SELECT hospital_ownership
                               FROM dim_hospital
                               WHERE hospital_type = 'Acute Care Hospitals'
                               GROUP BY hospital_ownership
                               HAVING COUNT(*) >= 50)
GROUP BY h.hospital_ownership, value_group
ORDER BY h.hospital_ownership, value_group;


-- ----------------------------------------------------------------------------
-- 5.3  Do the ownership differences hold in every region of the country?
-- Description:  Share of 4-5 star hospitals by Census region and ownership
--               group (for-profit, non-profit, government). Checks whether a
--               regional effect is hiding behind the ownership effect.
-- Metabase:     Bar chart. X = census_region, Y = pct_4_or_5_star, Series
--               breakout = ownership_group.
-- ----------------------------------------------------------------------------
WITH hospital_groups AS (
    SELECT h.facility_id,
           h.overall_rating,
           s.mspb_ratio,
           CASE
               WHEN h.state IN ('CT','ME','MA','NH','RI','VT','NJ','NY','PA')
                    THEN 'Northeast'
               WHEN h.state IN ('IL','IN','MI','OH','WI','IA','KS','MN','MO',
                                'NE','ND','SD')
                    THEN 'Midwest'
               WHEN h.state IN ('DE','DC','FL','GA','MD','NC','SC','VA','WV',
                                'AL','KY','MS','TN','AR','LA','OK','TX')
                    THEN 'South'
               WHEN h.state IN ('AZ','CO','ID','MT','NV','NM','UT','WY',
                                'AK','CA','HI','OR','WA')
                    THEN 'West'
               ELSE 'Territories'
           END AS census_region,
           CASE
               WHEN h.hospital_ownership IN ('Proprietary', 'Physician')
                    THEN 'For-profit'
               WHEN h.hospital_ownership LIKE 'Voluntary non-profit%'
                    THEN 'Non-profit'
               ELSE 'Government'   -- state/local/federal, VA, DoD, tribal
           END AS ownership_group
    FROM dim_hospital h
    JOIN fact_spending s
         ON s.facility_id = h.facility_id AND s.measure_id = 'MSPB-1'
    WHERE s.mspb_ratio IS NOT NULL
      AND h.overall_rating IS NOT NULL
)
SELECT census_region,
       ownership_group,
       COUNT(*)                                             AS hospitals,
       ROUND(AVG(mspb_ratio), 3)                            AS avg_mspb,
       ROUND(AVG(overall_rating), 2)                        AS avg_star_rating,
       ROUND(100.0 * COUNT(*) FILTER (WHERE overall_rating >= 4)
             / COUNT(*), 1)                                 AS pct_4_or_5_star
FROM hospital_groups
WHERE census_region <> 'Territories'
GROUP BY census_region, ownership_group
HAVING COUNT(*) >= 10
ORDER BY census_region, ownership_group;



-- ============================================================================
-- SECTION 6: GEOGRAPHY
-- Which states spend the most, and why?
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 6.1  Which states spend the most, and do they get better ratings?
-- Description:  Average spending ratio, star rating, and heart-failure
--               readmission rate for each state with 10+ hospitals.
-- Metabase:     Map > Region map > "United States". Region field = state,
--               Metric = avg_mspb (the other columns show on hover).
-- ----------------------------------------------------------------------------
SELECT h.state,
       COUNT(*)                                   AS hospitals,
       ROUND(AVG(s.mspb_ratio), 3)                AS avg_mspb,
       ROUND(AVG(h.overall_rating), 2)            AS avg_star_rating,
       ROUND(AVG(r.score), 2)                     AS avg_hf_readmission_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE s.mspb_ratio > 1)
             / COUNT(*), 1)                       AS pct_above_natl_spend
FROM dim_hospital h
JOIN fact_spending s
     ON s.facility_id = h.facility_id AND s.measure_id = 'MSPB-1'
LEFT JOIN fact_unplanned_visits r
     ON r.facility_id = h.facility_id AND r.measure_id = 'READM_30_HF'
WHERE s.mspb_ratio IS NOT NULL
GROUP BY h.state
HAVING COUNT(*) >= 10
ORDER BY avg_mspb DESC;


-- ----------------------------------------------------------------------------
-- 6.2  How do states compare on CMS star ratings?
-- Description:  Average CMS overall star rating for each state with 10+
--               hospitals, with the state's star and spending ranks. Read it
--               next to the 6.1 spending map.
-- Metabase:     Map > Region map > "United States". Region field = state, Metric = avg_star_rating (ranks and spending show on hover).
-- ----------------------------------------------------------------------------
WITH state_stats AS (
    SELECT h.state,
           COUNT(*)                        AS hospitals,
           AVG(s.mspb_ratio)               AS avg_ratio,
           AVG(h.overall_rating)           AS avg_stars
    FROM dim_hospital h
    JOIN fact_spending s
         ON s.facility_id = h.facility_id AND s.measure_id = 'MSPB-1'
    WHERE s.mspb_ratio IS NOT NULL
    GROUP BY h.state
    HAVING COUNT(*) >= 10
)
SELECT state,
       hospitals,
       ROUND(avg_stars, 2)                   AS avg_star_rating,
       RANK() OVER (ORDER BY avg_stars DESC) AS star_rank,
       ROUND(avg_ratio, 3)                   AS avg_spending_ratio,
       RANK() OVER (ORDER BY avg_ratio DESC) AS spending_rank
FROM state_stats
ORDER BY star_rank;


-- ----------------------------------------------------------------------------
-- 6.3  Do higher-spending states have lower heart-failure death rates?
-- Description:  One point per state: average Medicare spending ratio vs.
--               average 30-day heart-failure mortality rate.
-- Metabase:     Scatter. X = avg_spending_ratio, Y = avg_hf_mortality, Bubble
--               size = n_hospitals.
-- ----------------------------------------------------------------------------
SELECT h.state                       AS state,
       ROUND(AVG(cd.score), 2)       AS avg_hf_mortality,
       ROUND(AVG(s.mspb_ratio), 4)   AS avg_spending_ratio,
       COUNT(DISTINCT h.facility_id) AS n_hospitals
FROM dim_hospital h
JOIN fact_complications_deaths cd
     ON cd.facility_id = h.facility_id
JOIN fact_spending s
     ON s.facility_id = h.facility_id AND s.measure_id = 'MSPB-1'
WHERE cd.measure_id = 'MORT_30_HF'
  AND cd.score IS NOT NULL
  AND s.mspb_ratio IS NOT NULL
GROUP BY h.state
ORDER BY h.state;


-- ----------------------------------------------------------------------------
-- 6.4  Do states with more for-profit hospitals spend more?
-- Description:  One point per state with 10+ hospitals: share of hospitals
--               that are for-profit vs. the state's average spending ratio.
--               Links ownership (Section 5) to geography.
-- Metabase:     Scatter. X = pct_for_profit, Y = avg_mspb, Bubble size =
--               hospitals (hover shows the state).
-- ----------------------------------------------------------------------------
WITH state_mix AS (
    SELECT h.state,
           COUNT(*)                                            AS hospitals,
           ROUND(100.0 * COUNT(*) FILTER (WHERE h.hospital_ownership
                                          IN ('Proprietary', 'Physician'))
                 / COUNT(*), 1)                                AS pct_for_profit,
           ROUND(AVG(s.mspb_ratio), 3)                         AS avg_mspb,
           ROUND(AVG(h.overall_rating), 2)                     AS avg_star_rating
    FROM dim_hospital h
    JOIN fact_spending s
         ON s.facility_id = h.facility_id AND s.measure_id = 'MSPB-1'
    WHERE s.mspb_ratio IS NOT NULL
    GROUP BY h.state
    HAVING COUNT(*) >= 10
)
SELECT *
FROM state_mix
ORDER BY pct_for_profit DESC;