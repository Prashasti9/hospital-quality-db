--Visualization 1 Spending vs Readmission rate (Includes other fields like state and 
--ownership for use in metabase)
SELECT h.facility_id, 
	h.facility_name, 
	h.state, 
	h.hospital_ownership,
	s.mspb_ratio, 
	u.avg_readmission_pct,
	u.measures_reported
FROM fact_spending s
JOIN (SELECT facility_id, ROUND(AVG(score), 
	2) AS avg_readmission_pct,
    COUNT(*) AS measures_reported
    FROM fact_unplanned_visits
    WHERE measure_id LIKE 'READM_30_%' AND score IS NOT NULL
    GROUP BY facility_id) u ON u.facility_id = s.facility_id
JOIN dim_hospital h ON h.facility_id = s.facility_id
WHERE s.measure_id = 'MSPB-1'AND s.mspb_ratio IS NOT NULL
ORDER BY s.mspb_ratio;

--Visualization 2 Spending vs Multiple Quality Outcome Fields
--*Did ask Claude for help generating this query
WITH spend AS (
    SELECT facility_id,
           mspb_ratio,
           NTILE(4) OVER (ORDER BY mspb_ratio) AS spend_quartile
    FROM fact_spending
    WHERE measure_id = 'MSPB-1'
      AND mspb_ratio IS NOT NULL
),
mortality AS (
    SELECT facility_id, AVG(score) AS avg_mortality_pct
    FROM fact_complications_deaths
    WHERE measure_id LIKE 'MORT_30_%'
      AND score IS NOT NULL
    GROUP BY facility_id
),
safety AS (
    SELECT facility_id, score AS psi_90
    FROM fact_complications_deaths
    WHERE measure_id = 'PSI_90'
      AND score IS NOT NULL
),
infections AS (
    SELECT facility_id, AVG(score) AS avg_sir
    FROM fact_infections
    WHERE measure_id LIKE '%SIR'
      AND score IS NOT NULL
    GROUP BY facility_id
),
readmit AS (
    SELECT facility_id, AVG(score) AS readmission_rate_pct
    FROM fact_unplanned_visits
    WHERE measure_id LIKE 'READM_30_%'
      AND score IS NOT NULL
    GROUP BY facility_id
),
patient AS (
    SELECT facility_id, star_rating AS patient_stars
    FROM fact_patient_survey
    WHERE measure_id = 'H_STAR_RATING'
      AND star_rating IS NOT NULL
)
SELECT sp.spend_quartile,
       CASE sp.spend_quartile
            WHEN 1 THEN 'Q1 Lowest spend'
            WHEN 2 THEN 'Q2'
            WHEN 3 THEN 'Q3'
            WHEN 4 THEN 'Q4 Highest spend'
       END                                   AS spend_group,
       COUNT(*)                              AS hospitals,
       ROUND(MIN(sp.mspb_ratio), 2)          AS min_mspb,
       ROUND(MAX(sp.mspb_ratio), 2)          AS max_mspb,
       ROUND(AVG(m.avg_mortality_pct), 2)    AS avg_mortality_pct,
       ROUND(AVG(sf.psi_90), 3)              AS avg_psi_90,
       ROUND(AVG(i.avg_sir), 3)              AS avg_infection_sir,
       ROUND(AVG(r.readmission_rate_pct), 2) AS avg_readmission_pct,
       ROUND(AVG(p.patient_stars), 2)        AS avg_patient_stars,
       COUNT(m.facility_id)                  AS n_mortality,
       COUNT(i.facility_id)                  AS n_infections,
       COUNT(r.facility_id)                  AS n_readmit,
       COUNT(p.facility_id)                  AS n_patient
FROM spend sp
LEFT JOIN mortality  m  ON m.facility_id  = sp.facility_id
LEFT JOIN safety     sf ON sf.facility_id = sp.facility_id
LEFT JOIN infections i  ON i.facility_id  = sp.facility_id
LEFT JOIN readmit    r  ON r.facility_id  = sp.facility_id
LEFT JOIN patient    p  ON p.facility_id  = sp.facility_id
GROUP BY sp.spend_quartile
ORDER BY sp.spend_quartile;

--Visualization 3: Star Rating vs Several Fields (Do patients accurately rate the quality
--of their care)
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
WHERE s.measure_id = 'MSPB-1' AND s.mspb_ratio IS NOT NULL 
AND rec.answer_percent IS NOT NULL AND rec.completed_surveys >= 100
ORDER BY s.mspb_ratio DESC, star.star_rating;



SELECT measure_id, COUNT(*) FROM fact_spending GROUP BY measure_id;

SELECT measure_id, measure_name
FROM dim_measure
WHERE measure_domain = 'Unplanned Visits';

SELECT footnote, compared_to_national, COUNT(*)
FROM fact_unplanned_visits
WHERE measure_id = 'Hybrid_HWR'
GROUP BY footnote, compared_to_national;