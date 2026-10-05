-- ============================================================================
-- Brendan Waterval - Dashboard: "Does Spending Buy Quality?"
-- DSAI-691 Group 6, hospital_quality database (run create_and_load.sql first)
--
-- Story: Medicare pays some hospitals far more per patient than others.
-- Do the expensive hospitals deliver better care? We look at it nationally,
-- by state, by region + ownership, hospital by hospital, and end with the
-- hospitals that give the best quality for the lowest cost. Q6-Q8 then ask
-- WHY: patient experience? infections? the for-profit mix of each state?
--
-- Spending = fact_spending.mspb_ratio (Medicare Spending Per Beneficiary,
--            1.00 = national average, 1.10 = 10% more than average)
-- Quality  = dim_hospital.overall_rating (CMS 1-5 stars)
--            READM_30_HF  heart failure 30-day readmission rate (%, lower = better)
--            MORT_30_HF   heart failure 30-day death rate      (%, lower = better)
--            PSI_90       patient safety composite             (lower = better)
--
-- Join safety: every fact table has PRIMARY KEY (facility_id, measure_id), so
-- joining a fact table on facility_id AND one measure_id returns at most one
-- row per hospital. No join in this file can inflate row counts.
--
-- Run all:  psql -d hospital_quality -f brendan_waterval_dashboard_queries.sql
-- Metabase: paste ONE query (without the comments is fine) into a new SQL question.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Q1. National: does quality improve as spending goes up?
-- Hospitals are split into 4 equal-sized spending quartiles with NTILE(4),
-- then each quartile's average quality is compared.
-- Techniques: CTE, 4 LEFT JOINs across 3 fact tables, NTILE window function,
--             GROUP BY with COUNT / MIN / MAX / AVG
-- Metabase:  Combo chart. X = spending_quartile.
--            Bars = avg_star_rating, Line = avg_hf_readmission_pct
--            (put the line on the right-hand axis)
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
-- Q2. By state: which states spend the most, and do they get better ratings?
-- Techniques: JOIN, LEFT JOIN, GROUP BY state, AVG / COUNT,
--             HAVING to drop states with too few hospitals to compare
-- Metabase:  Map > Region map > "United States". Region field = state,
--            Metric = avg_mspb. (avg_star_rating etc. show on hover.)
--            Second option: duplicate the question as a Scatter,
--            X = avg_mspb, Y = avg_star_rating, bubble size = hospitals.
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
-- Q3. By region and ownership: who runs the high-quality hospitals, and
--     what do they cost?
-- States are mapped to the 4 U.S. Census regions, and the 12 CMS ownership
-- types are collapsed into For-profit / Non-profit / Government.
-- Techniques: CTE, CASE bucketing, JOIN, GROUP BY two dimensions,
--             COUNT(*) FILTER, HAVING
-- Metabase:  Bar chart. X = census_region, Series breakout = ownership_group,
--            Y = pct_4_or_5_star. (Duplicate with Y = avg_mspb to show cost
--            side by side on the dashboard.)
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


-- ----------------------------------------------------------------------------
-- Q4. Hospital by hospital: is there any real link between spending and
--     readmissions?
-- One point per hospital. Limited to hospitals with 150+ heart failure cases
-- so the rates are stable (also keeps results under Metabase's 2,000-row
-- chart limit). The window functions add the overall correlation and each
-- hospital's spending percentile to every row for the tooltip.
-- Techniques: 2 JOINs, filtering, CORR() and PERCENT_RANK() window functions
-- Metabase:  Scatter. X = mspb_ratio, Y = hf_readmission_pct,
--            Series breakout = star_rating. Hover shows name/city/state.
-- ----------------------------------------------------------------------------
SELECT h.facility_name,
       h.city_town,
       h.state,
       COALESCE(h.overall_rating::TEXT || ' stars', 'Not rated')  AS star_rating,
       s.mspb_ratio,
       r.score                                                   AS hf_readmission_pct,
       ROUND((100 * PERCENT_RANK() OVER (ORDER BY s.mspb_ratio))::NUMERIC, 1)
                                                                 AS spend_percentile,
       ROUND(CORR(s.mspb_ratio, r.score) OVER ()::NUMERIC, 3)    AS natl_correlation
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
-- Q5. The best-value hospitals: top 3 per state that combine high quality
--     (4-5 stars) with the lowest spending.
-- Techniques: CTE, JOIN + LEFT JOIN, AVG() OVER (PARTITION BY state) and
--             RANK() OVER (PARTITION BY state ORDER BY ...) window functions,
--             filtering on the window result
-- Metabase:  Table. Add conditional formatting on mspb_vs_state_avg
--            (green = below 0). Optional: add a dashboard filter on state.
-- ----------------------------------------------------------------------------
WITH rated AS (
    SELECT h.facility_id,
           h.facility_name,
           h.city_town,
           h.county_parish,
           h.zip_code,
           h.state,
           h.overall_rating,
           s.mspb_ratio,
           r.score AS hf_readmission_pct,
           ROUND(s.mspb_ratio - AVG(s.mspb_ratio) OVER (PARTITION BY h.state), 3)
                                                             AS mspb_vs_state_avg
    FROM dim_hospital h
    JOIN fact_spending s
         ON s.facility_id = h.facility_id AND s.measure_id = 'MSPB-1'
    LEFT JOIN fact_unplanned_visits r
         ON r.facility_id = h.facility_id AND r.measure_id = 'READM_30_HF'
    WHERE s.mspb_ratio IS NOT NULL
),
ranked AS (
    SELECT *,
           RANK() OVER (PARTITION BY state
                        ORDER BY mspb_ratio, overall_rating DESC) AS value_rank
    FROM rated
    WHERE overall_rating >= 4
)
SELECT state,
       value_rank,
       facility_name,
       city_town,
       county_parish,
       zip_code,
       overall_rating,
       mspb_ratio,
       mspb_vs_state_avg,
       hf_readmission_pct
FROM ranked
WHERE value_rank <= 3
ORDER BY state, value_rank;


-- ============================================================================
-- "WHY" QUERIES - Q1 showed high-spending hospitals earn FEWER stars.
-- Q6-Q8 dig into why.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Q6. WHY do high-spending hospitals get fewer stars?
--     Is it how patients experience their stay?
-- Compares patient-survey star ratings (HCAHPS) for the lowest- vs highest-
-- spending quartile, topic by topic. Biggest gap = biggest reason.
-- Techniques: CTE, NTILE window, 3-table JOIN (fact_spending, fact_patient_
--             survey, dim_measure), AVG(...) FILTER to pivot quartiles into
--             columns, GROUP BY, HAVING
-- Metabase:  Row chart. X = survey_topic, Y = star_gap (sorted, most negative
--            first). Or Bar with Y = lowest_spend_stars AND highest_spend_stars.
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
-- Q7. WHY isn't it clinical safety? Do high spenders have more infections?
-- Average Standardized Infection Ratio (SIR, where 1.0 = expected number of
-- infections, lower = better) for each infection type, per spending quartile.
-- If the lines are flat or falling, the star gap in Q6 is about patient
-- experience, not about patients getting infected.
-- Techniques: CTE, NTILE window, 3-table JOIN (fact_spending, fact_infections,
--             dim_measure), GROUP BY two columns, AVG / COUNT, LIKE filter
-- Metabase:  Line chart. X = spending_quartile,
--            Series breakout = infection_type, Y = avg_infection_ratio.
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
-- Q8. WHY do some states spend so much more than others?
--     Is it the mix of for-profit hospitals?
-- One point per state: share of hospitals that are for-profit vs the state's
-- average spending. CORR() OVER () adds the correlation across states.
-- Techniques: CTE, JOIN, GROUP BY state, AVG / COUNT(*) FILTER, HAVING,
--             CORR() window function over the grouped result
-- Metabase:  Scatter. X = pct_for_profit, Y = avg_mspb, bubble size =
--            hospitals. (Hover shows the state.)
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
SELECT *,
       ROUND(CORR(pct_for_profit, avg_mspb) OVER ()::NUMERIC, 3) AS corr_for_profit_vs_spend
FROM state_mix
ORDER BY pct_for_profit DESC;
