# DSAI-691 Group 6: U.S. Hospital Quality & Cost

**Question:** Does higher hospital spending lead to better quality of care?

A PostgreSQL star schema built from six CMS (Medicare) hospital datasets,
explored with SQL and visualized in Metabase.

## What's in this repo

| File | What it does |
|---|---|
| `create_and_load.sql` | **The whole database in one run:** creates `hospital_quality`, downloads the 6 CMS files, builds the star schema with primary and foreign keys, converts types, validates the load, and runs exploratory queries |
| `run.sh` | Runs the SQL script from Terminal and saves the output to `build_log.txt` |
| `metabase_setup.py` | Connects Metabase to the database and creates starter questions and a dashboard |

## Star schema

Three dimension tables describe *which hospital*, *what was measured* and *when*;
five fact tables hold the measurements. Each fact row is one hospital × one measure.

```mermaid
erDiagram
  DIM_HOSPITAL ||--o{ FACT_COMPLICATIONS_DEATHS : "facility_id"
  DIM_HOSPITAL ||--o{ FACT_INFECTIONS : "facility_id"
  DIM_HOSPITAL ||--o{ FACT_UNPLANNED_VISITS : "facility_id"
  DIM_HOSPITAL ||--o{ FACT_PATIENT_SURVEY : "facility_id"
  DIM_HOSPITAL ||--o{ FACT_SPENDING : "facility_id"
  DIM_MEASURE ||--o{ FACT_COMPLICATIONS_DEATHS : "measure_id"
  DIM_MEASURE ||--o{ FACT_INFECTIONS : "measure_id"
  DIM_MEASURE ||--o{ FACT_UNPLANNED_VISITS : "measure_id"
  DIM_MEASURE ||--o{ FACT_PATIENT_SURVEY : "measure_id"
  DIM_MEASURE ||--o{ FACT_SPENDING : "measure_id"
  DIM_PERIOD |o--o{ FACT_COMPLICATIONS_DEATHS : "period_id"
  DIM_PERIOD |o--o{ FACT_INFECTIONS : "period_id"
  DIM_PERIOD |o--o{ FACT_UNPLANNED_VISITS : "period_id"
  DIM_PERIOD |o--o{ FACT_PATIENT_SURVEY : "period_id"
  DIM_PERIOD |o--o{ FACT_SPENDING : "period_id"

  DIM_HOSPITAL {
    text facility_id PK
    text facility_name
    text city_town
    char state
    text county_parish
    text zip_code
    text hospital_type
    text hospital_ownership
    boolean emergency_services
    boolean birthing_friendly
    smallint overall_rating
  }
  DIM_MEASURE {
    text measure_id PK
    text measure_name
    text measure_detail
    text measure_domain
  }
  DIM_PERIOD {
    serial period_id PK
    date start_date
    date end_date
  }
  FACT_COMPLICATIONS_DEATHS {
    text facility_id PK,FK
    text measure_id PK,FK
    int period_id FK
    text compared_to_national
    numeric denominator
    numeric score
    numeric lower_estimate
    numeric higher_estimate
  }
  FACT_INFECTIONS {
    text facility_id PK,FK
    text measure_id PK,FK
    int period_id FK
    text compared_to_national
    numeric score
  }
  FACT_UNPLANNED_VISITS {
    text facility_id PK,FK
    text measure_id PK,FK
    int period_id FK
    text compared_to_national
    numeric score
    int number_of_patients
    int number_of_patients_returned
  }
  FACT_PATIENT_SURVEY {
    text facility_id PK,FK
    text measure_id PK,FK
    int period_id FK
    smallint star_rating
    numeric answer_percent
    numeric linear_mean_value
    int completed_surveys
    numeric response_rate_percent
  }
  FACT_SPENDING {
    text facility_id PK,FK
    text measure_id PK,FK
    int period_id FK
    numeric mspb_ratio
  }
```

`load_log` records which CMS files were downloaded, their CMS release date, and rows loaded.

## Step 1: Build the database (one command)

Needs PostgreSQL 13+, the `postgres` superuser login, and internet.

**In pgAdmin 4:** right-click your server (for example "PostgreSQL 16") → **PSQL Tool**, then type:

```
\i '/Users/YOUR-NAME/hospital-quality-db/create_and_load.sql'
```

**Or in Terminal**, from this folder:

```bash
./run.sh
```

A full run takes a few minutes. It ends with `BUILD COMPLETE`. Rerunning rebuilds
everything from fresh CMS data. The CSVs are kept in `/Users/Shared/hospital_quality_data/`.

## Step 2: Connect Metabase (automated)

With Metabase running (`docker start metabase`) and its admin account already created:

```bash
python3 metabase_setup.py
```

It asks for your Metabase login and Postgres password, then creates a database
connection, a **Group 6: Hospital Quality** collection with 5 SQL questions, and a
**Task 2: Data loaded and connected** dashboard.

Manual alternative: Admin settings → Databases → Add database → PostgreSQL, with host
`host.docker.internal`, port `5432`, database `hospital_quality`.

## Data source

CMS Provider Data Catalog, Hospitals: https://data.cms.gov/provider-data/topics/hospitals

| Dataset | CMS ID |
|---|---|
| Hospital General Information | `xubh-q36u` |
| Complications and Deaths - Hospital | `ynj2-r877` |
| Healthcare Associated Infections - Hospital | `77hc-ibv8` |
| Unplanned Hospital Visits - Hospital | `632h-zaca` |
| Patient Survey (HCAHPS) - Hospital | `dgck-syfz` |
| Medicare Spending Per Beneficiary - Hospital | `rrqw-56er` |
