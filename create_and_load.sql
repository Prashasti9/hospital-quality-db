-- ============================================================================
-- create_and_load.sql
-- DSAI-691 Group 6: U.S. Hospital Quality & Cost
--
-- ONE script, ONE run: creates the hospital_quality database, downloads the six
-- CMS hospital datasets, builds a STAR SCHEMA with primary and foreign keys,
-- loads and type-converts the data, validates it, and runs exploratory queries.
--
--   Dimensions : dim_hospital, dim_measure, dim_period
--   Facts      : fact_complications_deaths, fact_infections,
--                fact_unplanned_visits, fact_patient_survey, fact_spending
--   Audit      : load_log (which CMS files were loaded, release date, row counts)
--
-- Source: CMS Provider Data Catalog, Hospitals
--   https://data.cms.gov/provider-data/topics/hospitals
--   Hospital General Information ................ xubh-q36u
--   Complications and Deaths - Hospital ......... ynj2-r877
--   Healthcare Associated Infections - Hospital . 77hc-ibv8
--   Unplanned Hospital Visits - Hospital ........ 632h-zaca
--   Patient Survey (HCAHPS) - Hospital .......... dgck-syfz
--   Medicare Spending Per Beneficiary - Hospital  rrqw-56er
-- Column layouts verified against the CMS Hospital Data Dictionary (July 2026)
-- and the live Hospital_General_Information.csv header.
--
-- HOW TO RUN (one command, no manual steps)
--   Option A, inside pgAdmin 4:
--     Right-click the server (e.g. "PostgreSQL 16") > PSQL Tool, then type:
--       \i '/full/path/to/create_and_load.sql'
--   Option B, Terminal:
--       psql -U postgres -d postgres -f create_and_load.sql
--   (Uses psql commands such as \c, so it runs in the PSQL Tool or psql,
--    not in the Query Tool.)
--
-- Requirements: PostgreSQL 13+, connect as the "postgres" superuser (downloading
-- uses COPY ... FROM PROGRAM with curl, which is built into macOS), internet.
-- Fully rerunnable: every run drops and rebuilds the database from fresh CMS data.
-- Downloaded files are kept in /Users/Shared/hospital_quality_data/ (set in section 3).
-- A full run takes a few minutes (roughly 100+ MB from CMS).
--
-- Load strategy (ELT):
--   1. Load each CSV as-is into an all-TEXT staging table (CMS files use
--      "Not Available", "Not Applicable" and blanks inside numeric/date columns).
--   2. Transform into typed, keyed star-schema tables using safe-cast helpers
--      that turn any non-numeric placeholder into NULL.
--   3. Audit what was converted, then drop staging.
-- ============================================================================

\set ON_ERROR_STOP on
\pset footer off
\pset pager off

-- ============================================================================
-- 0. CREATE THE DATABASE (drops and recreates it, so every run starts clean)
-- ============================================================================
\echo '=== 0. CREATE THE DATABASE ==='
\c postgres
DROP DATABASE IF EXISTS hospital_quality WITH (FORCE);  -- FORCE also closes Metabase's connection
CREATE DATABASE hospital_quality;
\c hospital_quality


-- ============================================================================
-- 1. SAFE-CAST HELPER FUNCTIONS
--    Return NULL instead of failing when a value is a text placeholder.
-- ============================================================================
\echo '=== 1. SAFE-CAST HELPER FUNCTIONS ==='
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

-- CMS lists Facility ID as numeric in some files, so '010001' can arrive as '10001'.
-- Left-pad to 6 characters so every file joins to dim_hospital (IDs like '01014F' are already 6).
CREATE FUNCTION to_fid(v TEXT) RETURNS TEXT
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN trim(v) = '' THEN NULL ELSE lpad(trim(v), 6, '0') END
$$;

CREATE FUNCTION to_txt(v TEXT) RETURNS TEXT          -- blank / "Not Available" -> NULL
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN trim(v) IN ('', 'Not Available', 'Not Applicable', 'N/A') THEN NULL
                ELSE trim(v) END
$$;


-- ============================================================================
-- 2. STAGING TABLES (all TEXT, columns in the exact CSV order)
-- ============================================================================
\echo '=== 2. STAGING TABLES ==='
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


-- ============================================================================
-- 3. DOWNLOAD THE CSVs FROM CMS AND LOAD THEM
--    CMS changes download links every quarterly release, but dataset IDs stay
--    fixed. So the script (a) downloads the CMS catalog, (b) finds the current
--    link for each dataset ID, (c) downloads each CSV with curl, (d) checks its
--    column count, and (e) loads it into staging.
--
--    >>> The ONLY line to change on another machine: the download folder. <<<
--    /Users/Shared is used because Postgres cannot write to Desktop/Documents/Downloads.
-- ============================================================================
\echo '=== 3. DOWNLOAD THE CSVs FROM CMS AND LOAD THEM ==='
SET cms.data_dir    = '/Users/Shared/hospital_quality_data';
SET cms.catalog_url = 'https://data.cms.gov/provider-data/api/1/metastore/schemas/dataset/items';

-- The 6 datasets this project uses: CMS dataset ID -> staging table, file name, expected columns
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

-- Receives the (empty) output of the download commands
CREATE TABLE staging.program_output (line TEXT);

-- Permanent record of what was downloaded and loaded (useful for the write-up and grading)
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

    -- (a) download the CMS catalog, then read it with Postgres' own file reader
    EXECUTE format('COPY staging.program_output FROM PROGRAM %L ' || raw_opts,
                   format('mkdir -p %L && curl -sSfL %L -o %L',
                          dir, cat_url, dir || '/cms_catalog.json'));
    catalog := pg_read_file(dir || '/cms_catalog.json')::jsonb;

    -- (b) match our 6 dataset IDs to their current download links
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

        -- (c) download the CSV into the folder
        EXECUTE format('COPY staging.program_output FROM PROGRAM %L ' || raw_opts,
                       format('curl -sSfL %L -o %L', d.url, local_path));

        -- (d) read the header line and check the column count
        head_bytes := pg_read_binary_file(local_path, 0, 8192);
        header := convert_from(substring(head_bytes FROM 1 FOR position('\x0a'::bytea IN head_bytes) - 1), 'UTF8');
        header := replace(replace(header, E'\uFEFF', ''), E'\r', '');
        n_cols := array_length(string_to_array(header, ','), 1);
        IF n_cols IS DISTINCT FROM d.expected_cols THEN
            RAISE EXCEPTION '% has % columns but % were expected. CMS changed the layout; update % in section 2.',
                            d.file_name, n_cols, d.expected_cols, d.staging_table;
        END IF;

        -- (e) load the saved file into its staging table
        EXECUTE format('COPY %s FROM %L WITH (FORMAT csv, HEADER true, ENCODING ''UTF8'')',
                       d.staging_table, local_path);
        EXECUTE format('SELECT COUNT(*) FROM %s', d.staging_table) INTO n_rows;

        INSERT INTO load_log (dataset_id, title, cms_released, download_url, local_file, rows_loaded)
        VALUES (d.dataset_id, d.title, NULLIF(d.released, '')::DATE, d.url, local_path, n_rows);
        RAISE NOTICE '  saved % and loaded % rows into %', local_path, n_rows, d.staging_table;
    END LOOP;
END $$;

-- What was downloaded and loaded (see the result grid)
SELECT dataset_id, title, cms_released, rows_loaded, local_file FROM load_log ORDER BY dataset_id;


-- ============================================================================
-- 4. STAR SCHEMA — DIMENSIONS
-- ============================================================================
\echo '=== 4. STAR SCHEMA — DIMENSIONS ==='

-- One row per hospital. facility_id and zip_code stay TEXT on purpose:
-- they are identifiers with leading zeros (e.g. '010001', '02115').
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

-- One row per quality/cost measure across all five fact tables.
CREATE TABLE dim_measure (
    measure_id      TEXT PRIMARY KEY,
    measure_name    TEXT NOT NULL,
    measure_detail  TEXT,                       -- HCAHPS answer description
    measure_domain  TEXT NOT NULL CHECK (measure_domain IN
                    ('Complications & Deaths', 'Infections', 'Unplanned Visits',
                     'Patient Experience', 'Spending'))
);

-- One row per distinct measurement window (CMS reports rolling periods).
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
       to_bool(emergency_services), COALESCE(upper(trim(meets_birthing_friendly)) = 'Y', FALSE),  -- file uses 'Y' or blank
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


-- ============================================================================
-- 5. STAR SCHEMA — FACT TABLES
--    Grain of every fact table: one row per hospital per measure.
--    Each fact has a composite PK and FKs to all three dimensions.
-- ============================================================================
\echo '=== 5. STAR SCHEMA — FACT TABLES ==='

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
    mspb_ratio   NUMERIC,     -- hospital spend / national median; 1.00 = national median
    footnote     TEXT,
    PRIMARY KEY (facility_id, measure_id)
);

-- The INNER JOIN to dim_hospital keeps only rows whose hospital exists,
-- so every foreign key is guaranteed to hold (dropped rows are counted in section 6).

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

-- Indexes on FK columns used for joins/filters in the Phase-3 dashboards
CREATE INDEX ON dim_hospital (state);
CREATE INDEX ON dim_hospital (hospital_ownership);
CREATE INDEX ON fact_complications_deaths (measure_id);
CREATE INDEX ON fact_infections (measure_id);
CREATE INDEX ON fact_unplanned_visits (measure_id);
CREATE INDEX ON fact_patient_survey (measure_id);


-- ============================================================================
-- 6. LOAD VALIDATION  (run while staging still exists)
-- ============================================================================
\echo '=== 6. LOAD VALIDATION ==='

-- 6a. Raw rows loaded vs rows landed in the star schema.
\echo ''
\echo '--- 6a. Raw rows loaded vs rows landed in the star schema.'
--     A gap means rows referenced a Facility ID missing from General Information.
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

-- 6b. Which non-numeric placeholders were converted to NULL in the score columns?
\echo ''
\echo '--- 6b. Which non-numeric placeholders were converted to NULL in the score columns?'
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

-- 6c. Staging has served its purpose; drop it so Metabase only shows the star schema.
\echo ''
\echo '--- 6c. Staging has served its purpose; drop it so Metabase only shows the star schema.'
DROP SCHEMA staging CASCADE;

-- 6d. Confirm the typed columns (everything that is no longer TEXT).
\echo ''
\echo '--- 6d. Confirm the typed columns (everything that is no longer TEXT).'
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND data_type <> 'text'
ORDER BY table_name, ordinal_position;


-- ============================================================================
-- 7. EXPLORATORY QUERIES  (understanding the data)
-- ============================================================================
\echo '=== 7. EXPLORATORY QUERIES ==='

-- 7a. Row count of every table in the star schema
\echo ''
\echo '--- 7a. Row count of every table in the star schema'
SELECT 'dim_hospital' AS table_name, COUNT(*) AS row_count FROM dim_hospital
UNION ALL SELECT 'dim_measure', COUNT(*) FROM dim_measure
UNION ALL SELECT 'dim_period', COUNT(*) FROM dim_period
UNION ALL SELECT 'fact_complications_deaths', COUNT(*) FROM fact_complications_deaths
UNION ALL SELECT 'fact_infections', COUNT(*) FROM fact_infections
UNION ALL SELECT 'fact_unplanned_visits', COUNT(*) FROM fact_unplanned_visits
UNION ALL SELECT 'fact_patient_survey', COUNT(*) FROM fact_patient_survey
UNION ALL SELECT 'fact_spending', COUNT(*) FROM fact_spending;

-- 7b. How many measures per domain?
\echo ''
\echo '--- 7b. How many measures per domain?'
SELECT measure_domain, COUNT(*) AS measures
FROM dim_measure GROUP BY measure_domain ORDER BY measures DESC;

-- 7c. Hospital mix: type x ownership, with share that has a star rating
\echo ''
\echo '--- 7c. Hospital mix: type x ownership, with share that has a star rating'
SELECT hospital_type, hospital_ownership,
       COUNT(*)                                        AS hospitals,
       ROUND(100.0 * COUNT(overall_rating) / COUNT(*), 1) AS pct_rated,
       ROUND(AVG(overall_rating), 2)                   AS avg_star_rating
FROM dim_hospital
GROUP BY hospital_type, hospital_ownership
ORDER BY hospitals DESC;

-- 7d. Distribution of overall star ratings (NULL = not rated)
\echo ''
\echo '--- 7d. Distribution of overall star ratings (NULL = not rated)'
SELECT overall_rating, COUNT(*) AS hospitals,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM dim_hospital GROUP BY overall_rating ORDER BY overall_rating;

-- 7e. Spending distribution: Medicare Spending per Beneficiary ratio
\echo ''
\echo '--- 7e. Spending distribution: Medicare Spending per Beneficiary ratio'
SELECT COUNT(mspb_ratio)                                             AS hospitals_with_score,
       MIN(mspb_ratio) AS min_ratio, MAX(mspb_ratio) AS max_ratio,
       ROUND(AVG(mspb_ratio), 3)                                     AS avg_ratio,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY mspb_ratio)       AS median_ratio
FROM fact_spending;

-- 7f. CORE STORY PREVIEW: does spending differ by overall star rating?
\echo ''
\echo '--- 7f. CORE STORY PREVIEW: does spending differ by overall star rating?'
SELECT h.overall_rating,
       COUNT(*)                    AS hospitals,
       ROUND(AVG(s.mspb_ratio), 3) AS avg_spending_ratio
FROM fact_spending s
JOIN dim_hospital h USING (facility_id)
WHERE h.overall_rating IS NOT NULL AND s.mspb_ratio IS NOT NULL
GROUP BY h.overall_rating
ORDER BY h.overall_rating;

-- 7g. Spending quintiles vs patient-experience summary star rating (window function)
\echo ''
\echo '--- 7g. Spending quintiles vs patient-experience summary star rating (window function)'
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

-- 7h. Mortality: share of hospital-measure results "worse than national", by ownership
\echo ''
\echo '--- 7h. Mortality: share of hospital-measure results "worse than national", by ownership'
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

-- 7i. Infections: average standardized infection ratio (SIR) by measure (1.0 = national benchmark)
\echo ''
\echo '--- 7i. Infections: average standardized infection ratio (SIR) by measure (1.0 = national benchmark)'
SELECT m.measure_id, m.measure_name,
       COUNT(f.score)          AS hospitals_reporting,
       ROUND(AVG(f.score), 3)  AS avg_sir
FROM fact_infections f
JOIN dim_measure m USING (measure_id)
WHERE f.measure_id LIKE '%SIR'
GROUP BY m.measure_id, m.measure_name
ORDER BY m.measure_id;

-- 7j. States: average spending ratio and average star rating side by side
\echo ''
\echo '--- 7j. States: average spending ratio and average star rating side by side'
SELECT h.state,
       COUNT(DISTINCT h.facility_id)   AS hospitals,
       ROUND(AVG(s.mspb_ratio), 3)     AS avg_spending_ratio,
       ROUND(AVG(h.overall_rating), 2) AS avg_star_rating
FROM dim_hospital h
LEFT JOIN fact_spending s USING (facility_id)
GROUP BY h.state
HAVING COUNT(s.mspb_ratio) >= 10
ORDER BY avg_spending_ratio DESC;

-- 7k. Readmissions: heart failure 30-day readmission rate by state (top 10 highest).
--     (CMS retired READM_30_HOSP_WIDE; its replacement Hybrid_HWR has no scores yet,
--      so we use READM_30_HF, one of the readmission measures CMS penalizes hospitals on.)
\echo ''
\echo '--- 7k. Readmissions: heart failure 30-day readmission rate by state (top 10 highest)'
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

-- 7l. Measurement windows covered by the data
\echo ''
\echo '--- 7l. Measurement windows covered by the data'
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

-- 7m. Spot check: compare one hospital against Medicare Care Compare
--     (search the hospital name at https://www.medicare.gov/care-compare/ to confirm)
\echo ''
\echo '--- 7m. Spot check one hospital against Medicare Care Compare'
SELECT h.facility_id, h.facility_name, h.city_town, h.state, h.hospital_ownership,
       h.overall_rating, s.mspb_ratio,
       (SELECT star_rating FROM fact_patient_survey p
         WHERE p.facility_id = h.facility_id AND p.measure_id = 'H_STAR_RATING') AS patient_survey_stars
FROM dim_hospital h
LEFT JOIN fact_spending s USING (facility_id)
WHERE h.facility_id = '010001';

\echo ''
\echo '=== BUILD COMPLETE: hospital_quality is ready ==='
