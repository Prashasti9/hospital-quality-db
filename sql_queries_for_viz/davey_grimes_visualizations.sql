-- VIZ 1 spending vs quality, one dot per state
-- Chart: SCATTER
-- X = avg_spending_ratio, Y = avg_star_rating, Bubble size = hospitals
-- The cloud slopes DOWN-RIGHT: higher-spending states rate lower.
-- Call out the quadrants in a text card: low-cost/high-quality winners

SELECT h.state, COUNT(s.mspb_ratio) AS hospitals, ROUND(AVG(s.mspb_ratio), 3) AS avg_spending_ratio, ROUND(AVG(h.overall_rating), 2) AS avg_star_rating
FROM dim_hospital h
JOIN fact_spending s ON s.facility_id = h.facility_id
WHERE s.mspb_ratio IS NOT NULL
GROUP BY h.state
HAVING COUNT(s.mspb_ratio) >= 10
ORDER BY avg_spending_ratio DESC;

-- VIZ 2
-- Chart: COMBO (bar + line)
-- X = hospital_ownership
-- Left axis (bars) = avg_star_rating
-- Right axis (line) = avg_spending_ratio 
-- Expect: Proprietary ~2.79 stars / ~1.018 spend (worst + priciest);
-- non-profits ~3.3 / ~0.99 (better + cheaper).

SELECT h.hospital_ownership, COUNT(*) AS hospitals, ROUND(AVG(h.overall_rating), 2) AS avg_star_rating, ROUND(AVG(s.mspb_ratio), 3) AS avg_spending_ratio
FROM dim_hospital h
LEFT JOIN fact_spending s ON s.facility_id = h.facility_id
WHERE h.hospital_type = 'Acute Care Hospitals'
GROUP BY h.hospital_ownership
HAVING COUNT(*) >= 20
ORDER BY avg_star_rating DESC;

-- VIZ 3  share of TOP-RATED hospitals collapses as spend rises
-- Chart: Bar
-- X = spending_level, Y = pct_top_rated
-- Verified result: Low 50.8% -> Average 40.2% -> High 26.2%
-- Half of the cheapest hospitals are 4-5 stars; only a quarter of the priciest.

SELECT CASE WHEN s.mspb_ratio < 0.95 THEN '1. Low (below 0.95)'
WHEN s.mspb_ratio <= 1.05 THEN '2. Average (0.95 to 1.05)'
ELSE '3. High (above 1.05)' END AS spending_level, COUNT(h.overall_rating) AS rated_hospitals, SUM(CASE WHEN h.overall_rating >= 4 THEN 1 ELSE 0 END) AS top_rated, ROUND(100.0 * SUM(CASE WHEN h.overall_rating >= 4 THEN 1 ELSE 0 END) / COUNT(h.overall_rating), 1) AS pct_top_rated
FROM fact_spending s
JOIN dim_hospital h ON h.facility_id = s.facility_id
WHERE s.mspb_ratio IS NOT NULL
AND h.overall_rating IS NOT NULL
GROUP BY spending_level
ORDER BY spending_level;

-- VIZ 4  infections don't track spending
-- Chart: Bar
-- X = spending_level,  Y = avg_infection_sir
-- Verified result:  Low 0.493   Average 0.553   High 0.516   (no real pattern)
-- SIR = Standardized Infection Ratio, lower = fewer infections than expected.
-- The story: money buys a better reputation score but NOT fewer infections.

WITH hosp_sir AS (
SELECT f.facility_id, AVG(f.score) AS avg_sir
FROM fact_infections f
WHERE f.measure_id LIKE '%SIR'
AND f.score IS NOT NULL
GROUP BY f.facility_id
)
SELECT CASE WHEN s.mspb_ratio <  0.95 THEN '1. Low (below 0.95)'
WHEN s.mspb_ratio <= 1.05 THEN '2. Average (0.95 to 1.05)'
ELSE '3. High (above 1.05)' END AS spending_level, COUNT(*) AS hospitals, ROUND(AVG(hs.avg_sir), 3) AS avg_infection_sir
FROM fact_spending s
JOIN hosp_sir hs ON hs.facility_id = s.facility_id
WHERE s.mspb_ratio IS NOT NULL
GROUP BY spending_level
ORDER BY spending_level;

-- VIZ 5 readmissions don't track spending
-- Chart: Bar
-- X = spending_level,  Y = avg_hf_readmission_pct
-- Verified result: Low 21.21% Average 21.35% High 21.58% (flat)
-- Higher = more patients bounce back within 30 days (worse). Spending the most
-- does NOT keep heart-failure patients out of the hospital.

SELECT CASE WHEN s.mspb_ratio < 0.95 THEN '1. Low (below 0.95)'
WHEN s.mspb_ratio <= 1.05 THEN '2. Average (0.95 to 1.05)'ELSE '3. High (above 1.05)' END AS spending_level, COUNT(f.score) AS hospitals, ROUND(AVG(f.score), 2) AS avg_hf_readmission_pct
FROM fact_spending s
JOIN fact_unplanned_visits f ON f.facility_id = s.facility_id
WHERE f.measure_id = 'READM_30_HF'
AND s.mspb_ratio IS NOT NULL
AND f.score IS NOT NULL
GROUP BY spending_level
ORDER BY spending_level;
