# Hospital Quality vs Spending (DSAI-691 Group 6)

Group project for DSAI-691 Relational Databases at USF.

Team: Davey Grimes, Seth Prisament, Prashasti Srivastava, Eric Smith, Brendan Waterval

## Project question

Our question is whether hospitals that spend more per Medicare patient give better care. We used public hospital data from CMS (Centers for Medicare & Medicaid
Services) and loaded it into PostgreSQL, then connected it to Metabase for charts.

## Data

All data comes from the CMS Provider Data Catalog:
https://data.cms.gov/provider-data/topics/hospitals

We used the hospital-level version of 6 datasets so everything can be joined on facility ID:

- Hospital General Information (xubh-q36u)
- Complications and Deaths - Hospital (ynj2-r877)
- Healthcare Associated Infections - Hospital (77hc-ibv8)
- Unplanned Hospital Visits - Hospital (632h-zaca)
- Patient Survey (HCAHPS) - Hospital (dgck-syfz)
- Medicare Spending Per Beneficiary - Hospital (rrqw-56er)

## Database design

We set it up as a star schema.

Dimension tables:
- dim_hospital - one row per hospital (name, state, type, ownership, star rating)
- dim_measure - one row per measure (what was measured and which category it belongs to)
- dim_period - the date ranges the measures cover

Fact tables (one row per hospital per measure):
- fact_complications_deaths
- fact_infections
- fact_unplanned_visits
- fact_patient_survey
- fact_spending

facility_id is the primary key in dim_hospital and a foreign key in every fact table.
Same idea for measure_id and period_id. There is also a small load_log table that shows
how many rows came in from each file.

```mermaid
erDiagram
  DIM_HOSPITAL ||--o{ FACT_COMPLICATIONS_DEATHS : facility_id
  DIM_HOSPITAL ||--o{ FACT_INFECTIONS : facility_id
  DIM_HOSPITAL ||--o{ FACT_UNPLANNED_VISITS : facility_id
  DIM_HOSPITAL ||--o{ FACT_PATIENT_SURVEY : facility_id
  DIM_HOSPITAL ||--o{ FACT_SPENDING : facility_id
  DIM_MEASURE ||--o{ FACT_COMPLICATIONS_DEATHS : measure_id
  DIM_MEASURE ||--o{ FACT_INFECTIONS : measure_id
  DIM_MEASURE ||--o{ FACT_UNPLANNED_VISITS : measure_id
  DIM_MEASURE ||--o{ FACT_PATIENT_SURVEY : measure_id
  DIM_MEASURE ||--o{ FACT_SPENDING : measure_id
  DIM_PERIOD |o--o{ FACT_COMPLICATIONS_DEATHS : period_id
  DIM_PERIOD |o--o{ FACT_INFECTIONS : period_id
  DIM_PERIOD |o--o{ FACT_UNPLANNED_VISITS : period_id
  DIM_PERIOD |o--o{ FACT_PATIENT_SURVEY : period_id
  DIM_PERIOD |o--o{ FACT_SPENDING : period_id
```

## How to run it

You need PostgreSQL + pgAdmin, your postgres password, and internet (the script
downloads the CSVs from CMS itself).

1. Clone the repo:
   ```
   cd ~
   git clone https://github.com/Prashasti9/hospital-quality-db.git
   ```
2. In pgAdmin, click your server and open the PSQL Tool (the `>_` button).
3. Run the script (change the path to your own username):
   ```
   \i '/Users/yourname/hospital-quality-db/create_and_load.sql'
   ```
4. Wait a few minutes. When it prints `BUILD COMPLETE`, refresh Databases in pgAdmin
   to see `hospital_quality`.

The script also runs `exploration.sql` at the end, so the exploratory query results
appear in the same window. You can also open `exploration.sql` in the Query Tool on
`hospital_quality` and run one query at a time (highlight it and press F5).

The script drops and recreates the database every time, so it can be run again.
The CSV files are saved in `/Users/Shared/hospital_quality_data/`.

We run it in the PSQL Tool instead of the Query Tool because the script creates the
database and then connects to it, and the Query Tool cannot switch databases in the
middle of a script.

## Metabase

Metabase runs in Docker. After starting it (`docker start metabase`) and creating your
Metabase account, connect it with:

```
python3 metabase/metabase_setup.py
```

The script uses the `requests` library (included with Anaconda; otherwise run
`pip3 install requests`).

It asks for your Metabase login and postgres password, adds the database connection,
and creates 5 questions and a dashboard in a "Group 6: Hospital Quality"
collection. You can also add the connection by hand in Admin settings > Databases
(host `host.docker.internal`, port 5432, database `hospital_quality`).

## How the script works

A step-by-step explanation of every script is in `metabase/SCRIPTS_EXPLAINED.md`.

1. Creates the `hospital_quality` database
2. Makes temporary raw tables (all TEXT) that match the CSV columns
3. Downloads each CSV with curl and loads it with COPY
4. Creates the dimension and fact tables with primary and foreign keys
5. Uses INSERT INTO ... SELECT to clean the raw data and fill the final tables
   (text like "Not Available" becomes NULL, numbers and dates get proper types)
6. Runs some checks (raw rows vs loaded rows, data types)
7. Runs the exploratory queries in `exploration.sql` (13 queries, such as star rating by
   ownership, spending vs star rating, and readmissions by state)

## Data issues we found

- CMS uses "Not Available" and "Not Applicable" inside number columns, so we load
  everything as TEXT first and convert it afterwards.
- Some files drop the leading zero in facility_id (010001 shows up as 10001), so we
  pad it back to 6 characters before joining.
- CMS retired the hospital-wide readmission measure (READM_30_HOSP_WIDE) and its
  replacement (Hybrid_HWR) has no scores yet, so we use the heart failure readmission
  rate (READM_30_HF) instead.
- Psychiatric and children's hospitals do not receive CMS star ratings, so they appear
  as "not rated".
