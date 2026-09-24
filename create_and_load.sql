-- create_and_load.sql
-- DSAI-691 Group 6: U.S. Hospital Quality & Cost
--
-- Creates the hospital_quality database, downloads 6 CMS hospital files,
-- loads them into temporary raw tables, then copies them into a star schema
-- (3 dimension tables + 5 fact tables) with primary and foreign keys.
-- At the end it also runs the exploratory queries in exploration.sql.
--
-- How to run (pgAdmin): right-click the server > PSQL Tool, then type
--   \i '/Users/<your-name>/hospital-quality-db/create_and_load.sql'
-- Needs: PostgreSQL 13+, login as postgres, internet connection.
-- Data: https://data.cms.gov/provider-data/topics/hospitals

\set ON_ERROR_STOP on
\pset footer off
\pset pager off


-- 1. Create database
\echo '=== 1. Create database ==='
\c postgres
DROP DATABASE IF EXISTS hospital_quality WITH (FORCE);
CREATE DATABASE hospital_quality;
\c hospital_quality

-- CMS dates are written as MM/DD/YYYY
SET datestyle = 'ISO, MDY';


-- 2. Raw tables: temporary, every column TEXT, same columns as the CSV files
\echo '=== 2. Raw tables ==='

CREATE TEMP TABLE raw_hospital_info (
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

CREATE TEMP TABLE raw_complications (
    facility_id TEXT, facility_name TEXT, address TEXT, city_town TEXT, state TEXT,
    zip_code TEXT, county_parish TEXT, telephone_number TEXT,
    measure_id TEXT, measure_name TEXT, compared_to_national TEXT, denominator TEXT,
    score TEXT, lower_estimate TEXT, higher_estimate TEXT, footnote TEXT,
    start_date TEXT, end_date TEXT
);

CREATE TEMP TABLE raw_infections (
    facility_id TEXT, facility_name TEXT, address TEXT, city_town TEXT, state TEXT,
    zip_code TEXT, county_parish TEXT, telephone_number TEXT,
    measure_id TEXT, measure_name TEXT, compared_to_national TEXT, score TEXT,
    footnote TEXT, start_date TEXT, end_date TEXT
);

CREATE TEMP TABLE raw_unplanned_visits (
    facility_id TEXT, facility_name TEXT, address TEXT, city_town TEXT, state TEXT,
    zip_code TEXT, county_parish TEXT, telephone_number TEXT,
    measure_id TEXT, measure_name TEXT, compared_to_national TEXT, denominator TEXT,
    score TEXT, lower_estimate TEXT, higher_estimate TEXT,
    number_of_patients TEXT, number_of_patients_returned TEXT, footnote TEXT,
    start_date TEXT, end_date TEXT
);

CREATE TEMP TABLE raw_patient_survey (
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

CREATE TEMP TABLE raw_spending (
    facility_id TEXT, facility_name TEXT, address TEXT, city_town TEXT, state TEXT,
    zip_code TEXT, county_parish TEXT, telephone_number TEXT,
    measure_id TEXT, measure_name TEXT, score TEXT, footnote TEXT,
    start_date TEXT, end_date TEXT
);


-- 3. Download each file from CMS, save it in /Users/Shared/hospital_quality_data,
--    and load it into its raw table
\echo '=== 3. Download and load CMS files ==='

COPY raw_hospital_info FROM PROGRAM
    'mkdir -p /Users/Shared/hospital_quality_data && cd /Users/Shared/hospital_quality_data && curl -sSfL -o Hospital_General_Information.csv "https://data.cms.gov/provider-data/api/1/datastore/query/xubh-q36u/0/download?format=csv" && cat Hospital_General_Information.csv'
    WITH (FORMAT csv, HEADER true);

COPY raw_complications FROM PROGRAM
    'cd /Users/Shared/hospital_quality_data && curl -sSfL -o Complications_and_Deaths-Hospital.csv "https://data.cms.gov/provider-data/api/1/datastore/query/ynj2-r877/0/download?format=csv" && cat Complications_and_Deaths-Hospital.csv'
    WITH (FORMAT csv, HEADER true);

COPY raw_infections FROM PROGRAM
    'cd /Users/Shared/hospital_quality_data && curl -sSfL -o Healthcare_Associated_Infections-Hospital.csv "https://data.cms.gov/provider-data/api/1/datastore/query/77hc-ibv8/0/download?format=csv" && cat Healthcare_Associated_Infections-Hospital.csv'
    WITH (FORMAT csv, HEADER true);

COPY raw_unplanned_visits FROM PROGRAM
    'cd /Users/Shared/hospital_quality_data && curl -sSfL -o Unplanned_Hospital_Visits-Hospital.csv "https://data.cms.gov/provider-data/api/1/datastore/query/632h-zaca/0/download?format=csv" && cat Unplanned_Hospital_Visits-Hospital.csv'
    WITH (FORMAT csv, HEADER true);

COPY raw_patient_survey FROM PROGRAM
    'cd /Users/Shared/hospital_quality_data && curl -sSfL -o HCAHPS-Hospital.csv "https://data.cms.gov/provider-data/api/1/datastore/query/dgck-syfz/0/download?format=csv" && cat HCAHPS-Hospital.csv'
    WITH (FORMAT csv, HEADER true);

COPY raw_spending FROM PROGRAM
    'cd /Users/Shared/hospital_quality_data && curl -sSfL -o Medicare_Hospital_Spending_Per_Patient-Hospital.csv "https://data.cms.gov/provider-data/api/1/datastore/query/rrqw-56er/0/download?format=csv" && cat Medicare_Hospital_Spending_Per_Patient-Hospital.csv'
    WITH (FORMAT csv, HEADER true);


-- 4. Dimension tables
\echo '=== 4. Dimension tables ==='

-- facility_id and zip_code stay TEXT because they have leading zeros ('010001')
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
    measure_domain  TEXT NOT NULL
);

CREATE TABLE dim_period (
    period_id   SERIAL PRIMARY KEY,
    start_date  DATE NOT NULL,
    end_date    DATE NOT NULL,
    UNIQUE (start_date, end_date)
);

-- Some files drop the leading zero from facility_id, so LPAD adds it back
INSERT INTO dim_hospital
SELECT LPAD(facility_id, 6, '0'),
       facility_name,
       NULLIF(address, ''),
       NULLIF(city_town, ''),
       state,
       NULLIF(zip_code, ''),
       NULLIF(county_parish, ''),
       NULLIF(telephone_number, ''),
       hospital_type,
       hospital_ownership,
       CASE emergency_services WHEN 'Yes' THEN TRUE WHEN 'No' THEN FALSE END,
       COALESCE(meets_birthing_friendly = 'Y', FALSE),
       CASE WHEN hospital_overall_rating IN ('1', '2', '3', '4', '5')
            THEN hospital_overall_rating::SMALLINT END
FROM raw_hospital_info;

INSERT INTO dim_measure (measure_id, measure_name, measure_detail, measure_domain)
SELECT measure_id, MIN(measure_name), NULL, 'Complications & Deaths'
FROM raw_complications GROUP BY measure_id
UNION ALL
SELECT measure_id, MIN(measure_name), NULL, 'Infections'
FROM raw_infections GROUP BY measure_id
UNION ALL
SELECT measure_id, MIN(measure_name), NULL, 'Unplanned Visits'
FROM raw_unplanned_visits GROUP BY measure_id
UNION ALL
SELECT hcahps_measure_id, MIN(hcahps_question), MIN(hcahps_answer_description), 'Patient Experience'
FROM raw_patient_survey GROUP BY hcahps_measure_id
UNION ALL
SELECT measure_id, MIN(measure_name), NULL, 'Spending'
FROM raw_spending GROUP BY measure_id;

INSERT INTO dim_period (start_date, end_date)
SELECT start_date::DATE, end_date::DATE FROM raw_complications    WHERE start_date <> '' AND end_date <> ''
UNION
SELECT start_date::DATE, end_date::DATE FROM raw_infections       WHERE start_date <> '' AND end_date <> ''
UNION
SELECT start_date::DATE, end_date::DATE FROM raw_unplanned_visits WHERE start_date <> '' AND end_date <> ''
UNION
SELECT start_date::DATE, end_date::DATE FROM raw_patient_survey   WHERE start_date <> '' AND end_date <> ''
UNION
SELECT start_date::DATE, end_date::DATE FROM raw_spending         WHERE start_date <> '' AND end_date <> '';


-- 5. Fact tables: one row per hospital per measure
--    Values like 'Not Available' become NULL.
--    score ~ '^-?[0-9.]+$' means "score looks like a number".
\echo '=== 5. Fact tables ==='

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

-- JOIN dim_hospital keeps only hospitals that exist, so the foreign keys always hold
INSERT INTO fact_complications_deaths
SELECT h.facility_id, r.measure_id, p.period_id,
       NULLIF(NULLIF(r.compared_to_national, 'Not Available'), ''),
       CASE WHEN r.denominator     ~ '^-?[0-9.]+$' THEN r.denominator::NUMERIC END,
       CASE WHEN r.score           ~ '^-?[0-9.]+$' THEN r.score::NUMERIC END,
       CASE WHEN r.lower_estimate  ~ '^-?[0-9.]+$' THEN r.lower_estimate::NUMERIC END,
       CASE WHEN r.higher_estimate ~ '^-?[0-9.]+$' THEN r.higher_estimate::NUMERIC END,
       NULLIF(r.footnote, '')
FROM raw_complications r
JOIN dim_hospital h ON h.facility_id = LPAD(r.facility_id, 6, '0')
LEFT JOIN dim_period p ON p.start_date = NULLIF(r.start_date, '')::DATE
                      AND p.end_date   = NULLIF(r.end_date, '')::DATE;

INSERT INTO fact_infections
SELECT h.facility_id, r.measure_id, p.period_id,
       NULLIF(NULLIF(r.compared_to_national, 'Not Available'), ''),
       CASE WHEN r.score ~ '^-?[0-9.]+$' THEN r.score::NUMERIC END,
       NULLIF(r.footnote, '')
FROM raw_infections r
JOIN dim_hospital h ON h.facility_id = LPAD(r.facility_id, 6, '0')
LEFT JOIN dim_period p ON p.start_date = NULLIF(r.start_date, '')::DATE
                      AND p.end_date   = NULLIF(r.end_date, '')::DATE;

INSERT INTO fact_unplanned_visits
SELECT h.facility_id, r.measure_id, p.period_id,
       NULLIF(NULLIF(r.compared_to_national, 'Not Available'), ''),
       CASE WHEN r.denominator     ~ '^-?[0-9.]+$' THEN r.denominator::NUMERIC END,
       CASE WHEN r.score           ~ '^-?[0-9.]+$' THEN r.score::NUMERIC END,
       CASE WHEN r.lower_estimate  ~ '^-?[0-9.]+$' THEN r.lower_estimate::NUMERIC END,
       CASE WHEN r.higher_estimate ~ '^-?[0-9.]+$' THEN r.higher_estimate::NUMERIC END,
       CASE WHEN REPLACE(r.number_of_patients, ',', '') ~ '^[0-9]+$'
            THEN REPLACE(r.number_of_patients, ',', '')::INTEGER END,
       CASE WHEN REPLACE(r.number_of_patients_returned, ',', '') ~ '^[0-9]+$'
            THEN REPLACE(r.number_of_patients_returned, ',', '')::INTEGER END,
       NULLIF(r.footnote, '')
FROM raw_unplanned_visits r
JOIN dim_hospital h ON h.facility_id = LPAD(r.facility_id, 6, '0')
LEFT JOIN dim_period p ON p.start_date = NULLIF(r.start_date, '')::DATE
                      AND p.end_date   = NULLIF(r.end_date, '')::DATE;

INSERT INTO fact_patient_survey
SELECT h.facility_id, r.hcahps_measure_id, p.period_id,
       CASE WHEN r.patient_survey_star_rating IN ('1', '2', '3', '4', '5')
            THEN r.patient_survey_star_rating::SMALLINT END,
       CASE WHEN r.hcahps_answer_percent    ~ '^-?[0-9.]+$' THEN r.hcahps_answer_percent::NUMERIC END,
       CASE WHEN r.hcahps_linear_mean_value ~ '^-?[0-9.]+$' THEN r.hcahps_linear_mean_value::NUMERIC END,
       CASE WHEN REPLACE(r.number_of_completed_surveys, ',', '') ~ '^[0-9]+$'
            THEN REPLACE(r.number_of_completed_surveys, ',', '')::INTEGER END,
       CASE WHEN r.survey_response_rate_percent ~ '^-?[0-9.]+$' THEN r.survey_response_rate_percent::NUMERIC END
FROM raw_patient_survey r
JOIN dim_hospital h ON h.facility_id = LPAD(r.facility_id, 6, '0')
LEFT JOIN dim_period p ON p.start_date = NULLIF(r.start_date, '')::DATE
                      AND p.end_date   = NULLIF(r.end_date, '')::DATE;

INSERT INTO fact_spending
SELECT h.facility_id, r.measure_id, p.period_id,
       CASE WHEN r.score ~ '^-?[0-9.]+$' THEN r.score::NUMERIC END,
       NULLIF(r.footnote, '')
FROM raw_spending r
JOIN dim_hospital h ON h.facility_id = LPAD(r.facility_id, 6, '0')
LEFT JOIN dim_period p ON p.start_date = NULLIF(r.start_date, '')::DATE
                      AND p.end_date   = NULLIF(r.end_date, '')::DATE;

-- Record of what was loaded
CREATE TABLE load_log (
    dataset_id   TEXT PRIMARY KEY,
    title        TEXT,
    local_file   TEXT,
    rows_loaded  INTEGER,
    loaded_at    TIMESTAMP DEFAULT now()
);

INSERT INTO load_log (dataset_id, title, local_file, rows_loaded) VALUES
('xubh-q36u', 'Hospital General Information',
 '/Users/Shared/hospital_quality_data/Hospital_General_Information.csv',
 (SELECT COUNT(*) FROM raw_hospital_info)),
('ynj2-r877', 'Complications and Deaths - Hospital',
 '/Users/Shared/hospital_quality_data/Complications_and_Deaths-Hospital.csv',
 (SELECT COUNT(*) FROM raw_complications)),
('77hc-ibv8', 'Healthcare Associated Infections - Hospital',
 '/Users/Shared/hospital_quality_data/Healthcare_Associated_Infections-Hospital.csv',
 (SELECT COUNT(*) FROM raw_infections)),
('632h-zaca', 'Unplanned Hospital Visits - Hospital',
 '/Users/Shared/hospital_quality_data/Unplanned_Hospital_Visits-Hospital.csv',
 (SELECT COUNT(*) FROM raw_unplanned_visits)),
('dgck-syfz', 'Patient Survey (HCAHPS) - Hospital',
 '/Users/Shared/hospital_quality_data/HCAHPS-Hospital.csv',
 (SELECT COUNT(*) FROM raw_patient_survey)),
('rrqw-56er', 'Medicare Spending Per Beneficiary - Hospital',
 '/Users/Shared/hospital_quality_data/Medicare_Hospital_Spending_Per_Patient-Hospital.csv',
 (SELECT COUNT(*) FROM raw_spending));


-- 6. Load checks
\echo '=== 6. Load checks ==='

\echo ''
\echo '--- 6a. Rows in raw files vs rows loaded'
SELECT 'hospital info' AS source,
       (SELECT COUNT(*) FROM raw_hospital_info)         AS raw_rows,
       (SELECT COUNT(*) FROM dim_hospital)              AS loaded_rows
UNION ALL
SELECT 'complications and deaths',
       (SELECT COUNT(*) FROM raw_complications),
       (SELECT COUNT(*) FROM fact_complications_deaths)
UNION ALL
SELECT 'infections',
       (SELECT COUNT(*) FROM raw_infections),
       (SELECT COUNT(*) FROM fact_infections)
UNION ALL
SELECT 'unplanned visits',
       (SELECT COUNT(*) FROM raw_unplanned_visits),
       (SELECT COUNT(*) FROM fact_unplanned_visits)
UNION ALL
SELECT 'patient survey',
       (SELECT COUNT(*) FROM raw_patient_survey),
       (SELECT COUNT(*) FROM fact_patient_survey)
UNION ALL
SELECT 'spending',
       (SELECT COUNT(*) FROM raw_spending),
       (SELECT COUNT(*) FROM fact_spending);

\echo ''
\echo '--- 6b. Rows with no score (CMS reported Not Available)'
SELECT 'complications and deaths' AS fact_table, COUNT(*) AS total_rows,
       SUM(CASE WHEN score IS NULL THEN 1 ELSE 0 END) AS rows_without_score
FROM fact_complications_deaths
UNION ALL
SELECT 'infections', COUNT(*), SUM(CASE WHEN score IS NULL THEN 1 ELSE 0 END)
FROM fact_infections
UNION ALL
SELECT 'unplanned visits', COUNT(*), SUM(CASE WHEN score IS NULL THEN 1 ELSE 0 END)
FROM fact_unplanned_visits
UNION ALL
SELECT 'spending', COUNT(*), SUM(CASE WHEN mspb_ratio IS NULL THEN 1 ELSE 0 END)
FROM fact_spending;

\echo ''
\echo '--- 6c. Column data types'
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND data_type <> 'text'
ORDER BY table_name, ordinal_position;


-- 7. Exploratory queries (runs exploration.sql from the same folder)
\echo ''
\echo '=== 7. Exploratory queries (exploration.sql) ==='
\set ECHO all
\ir exploration.sql
\set ECHO none

\echo ''
\echo '=== BUILD COMPLETE: hospital_quality is ready ==='
