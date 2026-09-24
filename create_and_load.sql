-- create_and_load.sql
-- DSAI-691 Group 6: U.S. Hospital Quality & Cost
--
-- Creates the hospital_quality database, downloads 6 CMS hospital files,
-- builds a star schema (3 dimension tables + 5 fact tables), loads the data
-- and runs checks and exploratory queries.
--
-- How to run (pgAdmin): right-click the server > PSQL Tool, then type
--   \i '/Users/<your-name>/hospital-quality-db/create_and_load.sql'
-- Needs: PostgreSQL 13+, login as postgres, internet connection.
-- Data: https://data.cms.gov/provider-data/topics/hospitals

\set ON_ERROR_STOP on
\pset footer off
\pset pager off

-- 0. Create database
\echo '=== 0. Create database ==='
\c postgres
DROP DATABASE IF EXISTS hospital_quality WITH (FORCE);
CREATE DATABASE hospital_quality;
\c hospital_quality

-- 1. Helper functions
\echo '=== 1. Helper functions ==='
CREATE FUNCTION to_num(v TEXT) RETURNS NUMERIC
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN replace(trim(v), ',', '') ~ '^-?[0-9]*\.?[0-9]+$'
                THEN replace(trim(v), ',', '')::NUMERIC END
$$;

CREATE FUNCTION to_int(v TEXT) RETURNS INTEGER
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN replace(trim(v), ',', '') ~ '^-?[0-9]+$'
                THEN replace(trim(v), ',', '')::INTEGER END
$$;

CREATE FUNCTION to_dt(v TEXT) RETURNS DATE
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN trim(v) ~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$'
                THEN to_date(trim(v), 'MM/DD/YYYY') END
$$;

CREATE FUNCTION to_bool(v TEXT) RETURNS BOOLEAN
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE upper(trim(v)) WHEN 'YES' THEN TRUE WHEN 'Y' THEN TRUE
                               WHEN 'NO'  THEN FALSE WHEN 'N' THEN FALSE END
$$;

CREATE FUNCTION to_fid(v TEXT) RETURNS TEXT
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN trim(v) = '' THEN NULL ELSE lpad(trim(v), 6, '0') END
$$;

CREATE FUNCTION to_txt(v TEXT) RETURNS TEXT
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN trim(v) IN ('', 'Not Available', 'Not Applicable', 'N/A') THEN NULL
                ELSE trim(v) END
$$;

-- 2. Staging tables
\echo '=== 2. Staging tables ==='
CREATE SCHEMA staging;

CREATE TABLE staging.hospital_general_information (
    facility_id TEXT, facility_name TEXT, address TEXT, city_town TEXT, state TEXT,
    zip_code TEXT, county_parish TEXT, telephone_number TEXT,
    hospital_type TEXT, hospital_ownership TEXT, emergency_services TEXT,
    meets_birthing_friendly TEXT, hospital_overall_rating TEXT,
    hospital_overall_rating_footnote TEXT,
    mort_group_measure_count TEXT, count_facility_mort_measures TEXT,
    count_mort_better TEXT, count_mort_no_different TEXT, count_mort_worse TEXT,
    mort_group_footnote TEXT,
    safety_group_measure_count TEXT, count_facility_safety_measures TEXT,
    count_safety_better TEXT, count_safety_no_different TEXT, count_safety_worse TEXT,
    safety_group_footnote TEXT,
    readm_group_measure_count TEXT, count_facility_readm_measures TEXT,
    count_readm_better TEXT, count_readm_no_different TEXT, count_readm_worse TEXT,
    readm_group_footnote TEXT,
    pt_exp_group_measure_count TEXT, count_facility_pt_exp_measures TEXT,
    pt_exp_group_footnote TEXT,
    te_group_measure_count TEXT, count_facility_te_measures TEXT, te_group_footnote TEXT
);

CREATE TABLE staging.complications_deaths (
    facility_id TEXT, facility_name TEXT, address TEXT, city_town TEXT, state TEXT,
    zip_code TEXT, county_parish TEXT, telephone_number TEXT,
    measure_id TEXT, measure_name TEXT, compared_to_national TEXT, denominator TEXT,
    score TEXT, lower_estimate TEXT, higher_estimate TEXT, footnote TEXT,
    start_date TEXT, end_date TEXT
);

CREATE TABLE staging.infections (
    facility_id TEXT, facility_name TEXT, address TEXT, city_town TEXT, state TEXT,
    zip_code TEXT, county_parish TEXT, telephone_number TEXT,
    measure_id TEXT, measure_name TEXT, compared_to_national TEXT, score TEXT,
    footnote TEXT, start_date TEXT, end_date TEXT
);

CREATE TABLE staging.unplanned_visits (
    facility_id TEXT, facility_name TEXT, address TEXT, city_town TEXT, state TEXT,
    zip_code TEXT, county_parish TEXT, telephone_number TEXT,
    measure_id TEXT, measure_name TEXT, compared_to_national TEXT, denominator TEXT,
    score TEXT, lower_estimate TEXT, higher_estimate TEXT,
    number_of_patients TEXT, number_of_patients_returned TEXT, footnote TEXT,
    start_date TEXT, end_date TEXT
);

CREATE TABLE staging.patient_survey (
    facility_id TEXT, facility_name TEXT, address TEXT, city_town TEXT, state TEXT,
    zip_code TEXT, county_parish TEXT, telephone_number TEXT,
    hcahps_measure_id TEXT, hcahps_question TEXT, hcahps_answer_description TEXT,
    patient_survey_star_rating TEXT, patient_survey_star_rating_footnote TEXT,
    hcahps_answer_percent TEXT, hcahps_answer_percent_footnote TEXT,
    hcahps_linear_mean_value TEXT,
    number_of_completed_surveys TEXT, number_of_completed_surveys_footnote TEXT,
    survey_response_rate_percent TEXT, survey_response_rate_percent_footnote TEXT,
    start_date TEXT, end_date TEXT
);

CREATE TABLE staging.spending (
    facility_id TEXT, facility_name TEXT, address TEXT, city_town TEXT, state TEXT,
    zip_code TEXT, county_parish TEXT, telephone_number TEXT,
    measure_id TEXT, measure_name TEXT, score TEXT, footnote TEXT,
    start_date TEXT, end_date TEXT
);

-- 3. Download and load CMS files
\echo '=== 3. Download and load CMS files ==='
-- folder where the CSV files are saved
SET cms.data_dir    = '/Users/Shared/hospital_quality_data';
SET cms.catalog_url = 'https://data.cms.gov/provider-data/api/1/metastore/schemas/dataset/items';

CREATE TABLE staging.cms_datasets (
    dataset_id     TEXT PRIMARY KEY,
    staging_table  TEXT NOT NULL,
    file_name      TEXT NOT NULL,
    expected_cols  INTEGER NOT NULL
);
INSERT INTO staging.cms_datasets VALUES
    ('xubh-q36u', 'staging.hospital_general_information', 'Hospital_General_Information.csv',                    38),
    ('ynj2-r877', 'staging.complications_deaths',         'Complications_and_Deaths-Hospital.csv',               18),
    ('77hc-ibv8', 'staging.infections',                   'Healthcare_Associated_Infections-Hospital.csv',       15),
    ('632h-zaca', 'staging.unplanned_visits',             'Unplanned_Hospital_Visits-Hospital.csv',              20),
    ('dgck-syfz', 'staging.patient_survey',               'HCAHPS-Hospital.csv',                                 22),
    ('rrqw-56er', 'staging.spending',                     'Medicare_Hospital_Spending_Per_Patient-Hospital.csv', 14);

CREATE TABLE staging.program_output (line TEXT);

CREATE TABLE load_log (
    dataset_id    TEXT PRIMARY KEY,
    title         TEXT,
    cms_released  DATE,
    download_url  TEXT,
    local_file    TEXT,
    rows_loaded   INTEGER,
    loaded_at     TIMESTAMP DEFAULT now()
);

DO $$
DECLARE
    dir        TEXT    := rtrim(current_setting('cms.data_dir'), '/');
    cat_url    TEXT    := current_setting('cms.catalog_url');
    raw_opts   TEXT    := $o$WITH (FORMAT csv, DELIMITER E'\x02', QUOTE E'\x01')$o$;
    catalog    JSONB;
    d          RECORD;
    local_path TEXT;
    head_bytes BYTEA;
    header     TEXT;
    n_cols     INTEGER;
    n_rows     INTEGER;
BEGIN
    RAISE NOTICE 'Download folder: %', dir;

    EXECUTE format('COPY staging.program_output FROM PROGRAM %L ' || raw_opts,
                   format('mkdir -p %L && curl -sSfL %L -o %L',
                          dir, cat_url, dir || '/cms_catalog.json'));
    catalog := pg_read_file(dir || '/cms_catalog.json')::jsonb;

    FOR d IN
        SELECT ds.*, item->>'title' AS title, item->>'released' AS released,
               item->'distribution'->0->>'downloadURL' AS url
        FROM staging.cms_datasets ds
        LEFT JOIN jsonb_array_elements(catalog) AS item
               ON item->>'identifier' = ds.dataset_id
        ORDER BY ds.dataset_id
    LOOP
        IF d.url IS NULL THEN
            RAISE EXCEPTION 'Dataset % (%) was not found in the CMS catalog', d.dataset_id, d.file_name;
        END IF;
        local_path := dir || '/' || d.file_name;
        RAISE NOTICE 'Downloading % (released %)', d.title, d.released;

        EXECUTE format('COPY staging.program_output FROM PROGRAM %L ' || raw_opts,
                       format('curl -sSfL %L -o %L', d.url, local_path));

        head_bytes := pg_read_binary_file(local_path, 0, 8192);
        header := convert_from(substring(head_bytes FROM 1 FOR position('\x0a'::bytea IN head_bytes) - 1), 'UTF8');
        header := replace(replace(header, E'\uFEFF', ''), E'\r', '');
        n_cols := array_length(string_to_array(header, ','), 1);
        IF n_cols IS DISTINCT FROM d.expected_cols THEN
            RAISE EXCEPTION '% has % columns but % were expected. CMS changed the layout; update % in section 2.',
                            d.file_name, n_cols, d.expected_cols, d.staging_table;
        END IF;

        EXECUTE format('COPY %s FROM %L WITH (FORMAT csv, HEADER true, ENCODING ''UTF8'')',
                       d.staging_table, local_path);
        EXECUTE format('SELECT COUNT(*) FROM %s', d.staging_table) INTO n_rows;

        INSERT INTO load_log (dataset_id, title, cms_released, download_url, local_file, rows_loaded)
        VALUES (d.dataset_id, d.title, NULLIF(d.released, '')::DATE, d.url, local_path, n_rows);
        RAISE NOTICE '  saved % and loaded % rows into %', local_path, n_rows, d.staging_table;
    END LOOP;
END $$;

SELECT dataset_id, title, cms_released, rows_loaded, local_file FROM load_log ORDER BY dataset_id;

-- 4. Dimension tables
\echo '=== 4. Dimension tables ==='

CREATE TABLE dim_hospital (
    facility_id        TEXT     PRIMARY KEY,
    facility_name      TEXT     NOT NULL,
    address            TEXT,
    city_town          TEXT,
    state              CHAR(2)  NOT NULL,
    zip_code           TEXT,
    county_parish      TEXT,
    telephone_number   TEXT,
    hospital_type      TEXT,
    hospital_ownership TEXT,
    emergency_services BOOLEAN,
    birthing_friendly  BOOLEAN,
    overall_rating     SMALLINT CHECK (overall_rating BETWEEN 1 AND 5)
);

CREATE TABLE dim_measure (
    measure_id      TEXT PRIMARY KEY,
    measure_name    TEXT NOT NULL,
    measure_detail  TEXT,
    measure_domain  TEXT NOT NULL CHECK (measure_domain IN
                    ('Complications & Deaths', 'Infections', 'Unplanned Visits',
                     'Patient Experience', 'Spending'))
);

CREATE TABLE dim_period (
    period_id   SERIAL PRIMARY KEY,
    start_date  DATE NOT NULL,
    end_date    DATE NOT NULL,
    UNIQUE (start_date, end_date),
    CHECK (end_date >= start_date)
);

INSERT INTO dim_hospital
SELECT DISTINCT ON (to_fid(facility_id))
       to_fid(facility_id), trim(facility_name), to_txt(address), to_txt(city_town),
       upper(trim(state)), to_txt(zip_code), to_txt(county_parish), to_txt(telephone_number),
       to_txt(hospital_type), to_txt(hospital_ownership),
       to_bool(emergency_services), COALESCE(upper(trim(meets_birthing_friendly)) = 'Y', FALSE),
       to_int(hospital_overall_rating)
FROM staging.hospital_general_information
WHERE to_fid(facility_id) IS NOT NULL
ORDER BY to_fid(facility_id);

INSERT INTO dim_measure (measure_id, measure_name, measure_detail, measure_domain)
SELECT DISTINCT ON (measure_id) measure_id, measure_name, measure_detail, measure_domain
FROM (
    SELECT trim(measure_id) AS measure_id, trim(measure_name) AS measure_name,
           NULL AS measure_detail, 'Complications & Deaths' AS measure_domain
    FROM staging.complications_deaths
    UNION ALL
    SELECT trim(measure_id), trim(measure_name), NULL, 'Infections'
    FROM staging.infections
    UNION ALL
    SELECT trim(measure_id), trim(measure_name), NULL, 'Unplanned Visits'
    FROM staging.unplanned_visits
    UNION ALL
    SELECT trim(hcahps_measure_id), trim(hcahps_question),
           to_txt(hcahps_answer_description), 'Patient Experience'
    FROM staging.patient_survey
    UNION ALL
    SELECT trim(measure_id), trim(measure_name), NULL, 'Spending'
    FROM staging.spending
) m
WHERE to_txt(measure_id) IS NOT NULL
ORDER BY measure_id;

INSERT INTO dim_period (start_date, end_date)
SELECT DISTINCT to_dt(start_date), to_dt(end_date)
FROM (
    SELECT start_date, end_date FROM staging.complications_deaths
    UNION SELECT start_date, end_date FROM staging.infections
    UNION SELECT start_date, end_date FROM staging.unplanned_visits
    UNION SELECT start_date, end_date FROM staging.patient_survey
    UNION SELECT start_date, end_date FROM staging.spending
) p
WHERE to_dt(start_date) IS NOT NULL AND to_dt(end_date) IS NOT NULL
ORDER BY 1, 2;

-- 5. Fact tables
\echo '=== 5. Fact tables ==='

-- one row per hospital per measure
CREATE TABLE fact_complications_deaths (
    facility_id          TEXT    NOT NULL REFERENCES dim_hospital (facility_id),
    measure_id           TEXT    NOT NULL REFERENCES dim_measure (measure_id),
    period_id            INTEGER REFERENCES dim_period (period_id),
    compared_to_national TEXT,
    denominator          NUMERIC,
    score                NUMERIC,
    lower_estimate       NUMERIC,
    higher_estimate      NUMERIC,
    footnote             TEXT,
    PRIMARY KEY (facility_id, measure_id)
);

CREATE TABLE fact_infections (
    facility_id          TEXT    NOT NULL REFERENCES dim_hospital (facility_id),
    measure_id           TEXT    NOT NULL REFERENCES dim_measure (measure_id),
    period_id            INTEGER REFERENCES dim_period (period_id),
    compared_to_national TEXT,
    score                NUMERIC,
    footnote             TEXT,
    PRIMARY KEY (facility_id, measure_id)
);

CREATE TABLE fact_unplanned_visits (
    facility_id                 TEXT    NOT NULL REFERENCES dim_hospital (facility_id),
    measure_id                  TEXT    NOT NULL REFERENCES dim_measure (measure_id),
    period_id                   INTEGER REFERENCES dim_period (period_id),
    compared_to_national        TEXT,
    denominator                 NUMERIC,
    score                       NUMERIC,
    lower_estimate              NUMERIC,
    higher_estimate             NUMERIC,
    number_of_patients          INTEGER,
    number_of_patients_returned INTEGER,
    footnote                    TEXT,
    PRIMARY KEY (facility_id, measure_id)
);

CREATE TABLE fact_patient_survey (
    facility_id           TEXT     NOT NULL REFERENCES dim_hospital (facility_id),
    measure_id            TEXT     NOT NULL REFERENCES dim_measure (measure_id),
    period_id             INTEGER  REFERENCES dim_period (period_id),
    star_rating           SMALLINT CHECK (star_rating BETWEEN 1 AND 5),
    answer_percent        NUMERIC,
    linear_mean_value     NUMERIC,
    completed_surveys     INTEGER,
    response_rate_percent NUMERIC,
    PRIMARY KEY (facility_id, measure_id)
);

CREATE TABLE fact_spending (
    facility_id  TEXT    NOT NULL REFERENCES dim_hospital (facility_id),
    measure_id   TEXT    NOT NULL REFERENCES dim_measure (measure_id),
    period_id    INTEGER REFERENCES dim_period (period_id),
    mspb_ratio   NUMERIC,
    footnote     TEXT,
    PRIMARY KEY (facility_id, measure_id)
);

INSERT INTO fact_complications_deaths
SELECT to_fid(s.facility_id), trim(s.measure_id), p.period_id,
       to_txt(s.compared_to_national), to_num(s.denominator), to_num(s.score),
       to_num(s.lower_estimate), to_num(s.higher_estimate), to_txt(s.footnote)
FROM staging.complications_deaths s
JOIN dim_hospital h ON h.facility_id = to_fid(s.facility_id)
LEFT JOIN dim_period p ON p.start_date = to_dt(s.start_date) AND p.end_date = to_dt(s.end_date);

INSERT INTO fact_infections
SELECT to_fid(s.facility_id), trim(s.measure_id), p.period_id,
       to_txt(s.compared_to_national), to_num(s.score), to_txt(s.footnote)
FROM staging.infections s
JOIN dim_hospital h ON h.facility_id = to_fid(s.facility_id)
LEFT JOIN dim_period p ON p.start_date = to_dt(s.start_date) AND p.end_date = to_dt(s.end_date);

INSERT INTO fact_unplanned_visits
SELECT to_fid(s.facility_id), trim(s.measure_id), p.period_id,
       to_txt(s.compared_to_national), to_num(s.denominator), to_num(s.score),
       to_num(s.lower_estimate), to_num(s.higher_estimate),
       to_int(s.number_of_patients), to_int(s.number_of_patients_returned),
       to_txt(s.footnote)
FROM staging.unplanned_visits s
JOIN dim_hospital h ON h.facility_id = to_fid(s.facility_id)
LEFT JOIN dim_period p ON p.start_date = to_dt(s.start_date) AND p.end_date = to_dt(s.end_date);

INSERT INTO fact_patient_survey
SELECT to_fid(s.facility_id), trim(s.hcahps_measure_id), p.period_id,
       to_int(s.patient_survey_star_rating), to_num(s.hcahps_answer_percent),
       to_num(s.hcahps_linear_mean_value), to_int(s.number_of_completed_surveys),
       to_num(s.survey_response_rate_percent)
FROM staging.patient_survey s
JOIN dim_hospital h ON h.facility_id = to_fid(s.facility_id)
LEFT JOIN dim_period p ON p.start_date = to_dt(s.start_date) AND p.end_date = to_dt(s.end_date);

INSERT INTO fact_spending
SELECT to_fid(s.facility_id), trim(s.measure_id), p.period_id,
       to_num(s.score), to_txt(s.footnote)
FROM staging.spending s
JOIN dim_hospital h ON h.facility_id = to_fid(s.facility_id)
LEFT JOIN dim_period p ON p.start_date = to_dt(s.start_date) AND p.end_date = to_dt(s.end_date);

CREATE INDEX ON dim_hospital (state);
CREATE INDEX ON dim_hospital (hospital_ownership);
CREATE INDEX ON fact_complications_deaths (measure_id);
CREATE INDEX ON fact_infections (measure_id);
CREATE INDEX ON fact_unplanned_visits (measure_id);
CREATE INDEX ON fact_patient_survey (measure_id);

-- 6. Load checks
\echo '=== 6. Load checks ==='

\echo ''
\echo '--- 6a. Rows in raw files vs rows loaded'
SELECT 'complications_deaths' AS source,
       (SELECT COUNT(*) FROM staging.complications_deaths) AS raw_rows,
       (SELECT COUNT(*) FROM fact_complications_deaths)    AS loaded_rows
UNION ALL SELECT 'infections',
       (SELECT COUNT(*) FROM staging.infections), (SELECT COUNT(*) FROM fact_infections)
UNION ALL SELECT 'unplanned_visits',
       (SELECT COUNT(*) FROM staging.unplanned_visits), (SELECT COUNT(*) FROM fact_unplanned_visits)
UNION ALL SELECT 'patient_survey',
       (SELECT COUNT(*) FROM staging.patient_survey), (SELECT COUNT(*) FROM fact_patient_survey)
UNION ALL SELECT 'spending',
       (SELECT COUNT(*) FROM staging.spending), (SELECT COUNT(*) FROM fact_spending)
UNION ALL SELECT 'hospital_general_information',
       (SELECT COUNT(*) FROM staging.hospital_general_information), (SELECT COUNT(*) FROM dim_hospital);

\echo ''
\echo '--- 6b. Placeholder values converted to NULL'
SELECT 'complications_deaths' AS source, score AS raw_value, COUNT(*) AS n
FROM staging.complications_deaths WHERE to_num(score) IS NULL GROUP BY score
UNION ALL
SELECT 'infections', score, COUNT(*)
FROM staging.infections WHERE to_num(score) IS NULL GROUP BY score
UNION ALL
SELECT 'unplanned_visits', score, COUNT(*)
FROM staging.unplanned_visits WHERE to_num(score) IS NULL GROUP BY score
UNION ALL
SELECT 'spending', score, COUNT(*)
FROM staging.spending WHERE to_num(score) IS NULL GROUP BY score
ORDER BY source, n DESC;

-- remove staging tables
DROP SCHEMA staging CASCADE;

\echo ''
\echo '--- 6d. Column data types'
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND data_type <> 'text'
ORDER BY table_name, ordinal_position;

-- 7. Exploratory queries
\echo '=== 7. Exploratory queries ==='

\echo ''
\echo '--- 7a. Rows per table'
SELECT 'dim_hospital' AS table_name, COUNT(*) AS row_count FROM dim_hospital
UNION ALL SELECT 'dim_measure', COUNT(*) FROM dim_measure
UNION ALL SELECT 'dim_period', COUNT(*) FROM dim_period
UNION ALL SELECT 'fact_complications_deaths', COUNT(*) FROM fact_complications_deaths
UNION ALL SELECT 'fact_infections', COUNT(*) FROM fact_infections
UNION ALL SELECT 'fact_unplanned_visits', COUNT(*) FROM fact_unplanned_visits
UNION ALL SELECT 'fact_patient_survey', COUNT(*) FROM fact_patient_survey
UNION ALL SELECT 'fact_spending', COUNT(*) FROM fact_spending;

\echo ''
\echo '--- 7b. Measures per domain'
SELECT measure_domain, COUNT(*) AS measures
FROM dim_measure GROUP BY measure_domain ORDER BY measures DESC;

\echo ''
\echo '--- 7c. Hospitals by type and ownership'
SELECT hospital_type, hospital_ownership,
       COUNT(*)                                        AS hospitals,
       ROUND(100.0 * COUNT(overall_rating) / COUNT(*), 1) AS pct_rated,
       ROUND(AVG(overall_rating), 2)                   AS avg_star_rating
FROM dim_hospital
GROUP BY hospital_type, hospital_ownership
ORDER BY hospitals DESC;

\echo ''
\echo '--- 7d. Overall star rating distribution'
SELECT overall_rating, COUNT(*) AS hospitals,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM dim_hospital GROUP BY overall_rating ORDER BY overall_rating;

\echo ''
\echo '--- 7e. Spending ratio summary'
SELECT COUNT(mspb_ratio)                                             AS hospitals_with_score,
       MIN(mspb_ratio) AS min_ratio, MAX(mspb_ratio) AS max_ratio,
       ROUND(AVG(mspb_ratio), 3)                                     AS avg_ratio,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY mspb_ratio)       AS median_ratio
FROM fact_spending;

\echo ''
\echo '--- 7f. Spending ratio by star rating'
SELECT h.overall_rating,
       COUNT(*)                    AS hospitals,
       ROUND(AVG(s.mspb_ratio), 3) AS avg_spending_ratio
FROM fact_spending s
JOIN dim_hospital h USING (facility_id)
WHERE h.overall_rating IS NOT NULL AND s.mspb_ratio IS NOT NULL
GROUP BY h.overall_rating
ORDER BY h.overall_rating;

\echo ''
\echo '--- 7g. Patient survey stars by spending quintile'
WITH spend AS (
    SELECT facility_id, mspb_ratio,
           NTILE(5) OVER (ORDER BY mspb_ratio) AS spending_quintile
    FROM fact_spending
    WHERE mspb_ratio IS NOT NULL
)
SELECT sp.spending_quintile,
       ROUND(MIN(sp.mspb_ratio), 2) || ' - ' || ROUND(MAX(sp.mspb_ratio), 2) AS ratio_range,
       COUNT(ps.star_rating)            AS hospitals_with_survey_star,
       ROUND(AVG(ps.star_rating), 2)    AS avg_patient_star
FROM spend sp
LEFT JOIN fact_patient_survey ps
       ON ps.facility_id = sp.facility_id AND ps.measure_id = 'H_STAR_RATING'
GROUP BY sp.spending_quintile
ORDER BY sp.spending_quintile;

\echo ''
\echo '--- 7h. Mortality results worse than national, by ownership'
SELECT h.hospital_ownership,
       COUNT(*) FILTER (WHERE f.compared_to_national IS NOT NULL)         AS rated_results,
       ROUND(100.0 * COUNT(*) FILTER (WHERE f.compared_to_national ILIKE 'Worse%')
             / NULLIF(COUNT(*) FILTER (WHERE f.compared_to_national IS NOT NULL), 0), 2)
                                                                           AS pct_worse
FROM fact_complications_deaths f
JOIN dim_hospital h USING (facility_id)
WHERE f.measure_id LIKE 'MORT%'
GROUP BY h.hospital_ownership
ORDER BY pct_worse DESC NULLS LAST;

\echo ''
\echo '--- 7i. Average infection ratio (SIR) by measure'
SELECT m.measure_id, m.measure_name,
       COUNT(f.score)          AS hospitals_reporting,
       ROUND(AVG(f.score), 3)  AS avg_sir
FROM fact_infections f
JOIN dim_measure m USING (measure_id)
WHERE f.measure_id LIKE '%SIR'
GROUP BY m.measure_id, m.measure_name
ORDER BY m.measure_id;

\echo ''
\echo '--- 7j. Spending and star rating by state'
SELECT h.state,
       COUNT(DISTINCT h.facility_id)   AS hospitals,
       ROUND(AVG(s.mspb_ratio), 3)     AS avg_spending_ratio,
       ROUND(AVG(h.overall_rating), 2) AS avg_star_rating
FROM dim_hospital h
LEFT JOIN fact_spending s USING (facility_id)
GROUP BY h.state
HAVING COUNT(s.mspb_ratio) >= 10
ORDER BY avg_spending_ratio DESC;

\echo ''
\echo '--- 7k. Top 10 states by heart failure readmission rate'
SELECT h.state,
       COUNT(f.score)         AS hospitals_reporting,
       ROUND(AVG(f.score), 2) AS avg_hf_readmission_rate_pct
FROM fact_unplanned_visits f
JOIN dim_hospital h USING (facility_id)
WHERE f.measure_id = 'READM_30_HF'
GROUP BY h.state
HAVING COUNT(f.score) >= 5
ORDER BY avg_hf_readmission_rate_pct DESC
LIMIT 10;

\echo ''
\echo '--- 7l. Measurement periods'
SELECT m.measure_domain, p.start_date, p.end_date, COUNT(*) AS results
FROM (
    SELECT measure_id, period_id FROM fact_complications_deaths
    UNION ALL SELECT measure_id, period_id FROM fact_infections
    UNION ALL SELECT measure_id, period_id FROM fact_unplanned_visits
    UNION ALL SELECT measure_id, period_id FROM fact_patient_survey
    UNION ALL SELECT measure_id, period_id FROM fact_spending
) f
JOIN dim_measure m USING (measure_id)
LEFT JOIN dim_period p USING (period_id)
GROUP BY m.measure_domain, p.start_date, p.end_date
ORDER BY m.measure_domain, p.start_date;

\echo ''
\echo '--- 7m. Spot check one hospital (compare with medicare.gov/care-compare)'
SELECT h.facility_id, h.facility_name, h.city_town, h.state, h.hospital_ownership,
       h.overall_rating, s.mspb_ratio,
       (SELECT star_rating FROM fact_patient_survey p
         WHERE p.facility_id = h.facility_id AND p.measure_id = 'H_STAR_RATING') AS patient_survey_stars
FROM dim_hospital h
LEFT JOIN fact_spending s USING (facility_id)
WHERE h.facility_id = '010001';

\echo ''
\echo '=== BUILD COMPLETE: hospital_quality is ready ==='
