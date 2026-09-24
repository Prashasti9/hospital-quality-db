# Script Guide

This file explains what each script in the repo does, step by step.

## Terms used

- **Database**: a set of tables, similar to a workbook with many sheets.
- **Table**: one sheet of data with rows and columns.
- **CSV file**: a text file where each line is a row and commas separate the columns.
- **SQL**: the language used to create tables and query data.
- **Primary key (PK)**: a column with a unique value for every row, like an ID number.
- **Foreign key (FK)**: a column that points to the primary key of another table. The
  database uses it to check that the two tables match. For example, a score cannot be
  saved for a hospital that does not exist.
- **NULL**: no value. This is not the same as zero.
- **pgAdmin**: the program we use to work with PostgreSQL.
- **PSQL Tool**: a command window inside pgAdmin that can run a whole script file.
- **Metabase**: the program we use to make charts and dashboards.
- **Docker**: runs Metabase inside a container on our laptops.

## Files in the repo

| File | Purpose |
|---|---|
| `create_and_load.sql` | Builds the database from the beginning |
| `exploration.sql` | 13 exploratory queries (they also run at the end of the build) |
| `metabase_setup.py` | Connects Metabase to the database and creates a dashboard |
| `run.sh` | Optional. Runs `create_and_load.sql` from Terminal instead of pgAdmin |
| `README.md` | Project overview and instructions |

---

## 1. create_and_load.sql

The script runs from top to bottom in 7 steps.

### Settings

```sql
\set ON_ERROR_STOP on
\pset footer off
\pset pager off
```

- `ON_ERROR_STOP on`: if any statement fails, the script stops at that point.
- `footer off`: hides the "(5 rows)" line under each result.
- `pager off`: shows all results at once instead of pausing at "(END)".

Lines that start with a backslash (`\`) are commands for the PSQL Tool, not SQL. The
Query Tool does not understand them, so this script is run in the PSQL Tool.

### Step 1: Create the database

```sql
\c postgres
DROP DATABASE IF EXISTS hospital_quality WITH (FORCE);
CREATE DATABASE hospital_quality;
\c hospital_quality
SET datestyle = 'ISO, MDY';
```

- `\c postgres`: connects to the default database. A database cannot be deleted while
  we are connected to it, so we move out of it first.
- `DROP DATABASE IF EXISTS ...`: deletes the old database if one exists, so every run
  starts from zero. `WITH (FORCE)` closes other connections to it, such as Metabase.
- `CREATE DATABASE hospital_quality`: creates a new, empty database.
- `\c hospital_quality`: connects to the new database. Everything after this line
  happens inside it.
- `SET datestyle = 'ISO, MDY'`: tells PostgreSQL that a date like `07/01/2024` is
  month/day/year, which is the format CMS uses.

### Step 2: Raw tables

```sql
CREATE TEMP TABLE raw_hospital_info (
    facility_id TEXT, facility_name TEXT, address TEXT, ...
);
```

- There are 6 raw tables, one for each CSV file.
- `TEMP` means the table is temporary. It is deleted automatically when the script
  finishes.
- Every column is `TEXT`. CMS writes words such as "Not Available" inside number
  columns. Loading those into a number column would fail, so we load everything as
  text first and convert it in step 5.
- The columns are in the same order as the columns in the CSV file.

### Step 3: Download and load the CMS files

```sql
COPY raw_hospital_info FROM PROGRAM
    'mkdir -p /Users/Shared/hospital_quality_data && cd /Users/Shared/hospital_quality_data
     && curl -sSfL -o Hospital_General_Information.csv "https://data.cms.gov/...xubh-q36u/..."
     && cat Hospital_General_Information.csv'
    WITH (FORMAT csv, HEADER true);
```

The text inside the quotes is a list of Mac Terminal commands. `&&` means "then, if the
previous command worked":

1. `mkdir -p /Users/Shared/hospital_quality_data`: creates the folder if it does not
   exist. Every Mac has `/Users/Shared`, and PostgreSQL is allowed to write there.
2. `cd ...`: moves into that folder.
3. `curl ... -o Hospital_General_Information.csv "https://..."`: downloads the file
   from the CMS website and saves it in the folder. The link contains the permanent
   dataset ID (`xubh-q36u`), so it still works after CMS updates the data.
4. `cat Hospital_General_Information.csv`: reads the file so COPY can load it.

The rest of the statement:
- `COPY raw_hospital_info FROM PROGRAM ...`: loads the output of those commands into
  the raw table.
- `FORMAT csv`: the data is separated by commas.
- `HEADER true`: skips the first line, which has the column names.

The same statement is repeated for all 6 files. If a download fails, for example with
no internet, the script stops with an error.

### Step 4: Dimension tables

```sql
CREATE TABLE dim_hospital (
    facility_id        TEXT     PRIMARY KEY,
    facility_name      TEXT     NOT NULL,
    state              CHAR(2)  NOT NULL,
    emergency_services BOOLEAN,
    overall_rating     SMALLINT CHECK (overall_rating BETWEEN 1 AND 5),
    ...
);
```

- `dim_hospital` has one row per hospital. `facility_id` is the primary key.
- `facility_id` and `zip_code` are stored as text because they have leading zeros
  (`010001`). Storing them as numbers would remove the zeros.
- `NOT NULL`: the column must have a value.
- `CHAR(2)`: exactly 2 characters, for state codes such as `CA`.
- `BOOLEAN`: true or false.
- `SMALLINT CHECK (... BETWEEN 1 AND 5)`: a small whole number between 1 and 5. The
  database rejects any other value.

Two more dimension tables are created:
- `dim_measure`: one row per measure (for example, the heart failure death rate), with
  its category.
- `dim_period`: one row per date range. `SERIAL` numbers the rows 1, 2, 3 automatically.

The dimension tables are filled from the raw tables:

```sql
INSERT INTO dim_hospital
SELECT LPAD(facility_id, 6, '0'),
       ...
       CASE emergency_services WHEN 'Yes' THEN TRUE WHEN 'No' THEN FALSE END,
       COALESCE(meets_birthing_friendly = 'Y', FALSE),
       CASE WHEN hospital_overall_rating IN ('1','2','3','4','5')
            THEN hospital_overall_rating::SMALLINT END
FROM raw_hospital_info;
```

- `INSERT INTO ... SELECT ...`: copies rows from one table to another and cleans them
  at the same time.
- `LPAD(facility_id, 6, '0')`: adds zeros on the left until the ID has 6 characters.
  Some CMS files write `10001` instead of `010001`.
- `CASE ... WHEN 'Yes' THEN TRUE ...`: changes Yes/No into true/false.
- `COALESCE(x = 'Y', FALSE)`: the birthing friendly column is either "Y" or blank. The
  result is true for "Y" and false otherwise.
- `CASE WHEN rating IN ('1',...,'5') THEN rating::SMALLINT END`: keeps only ratings from
  1 to 5 and converts them to numbers. Any other value, such as "Not Available", becomes
  NULL. `::SMALLINT` converts text to a number.

For `dim_measure`, `GROUP BY measure_id` gives one row per measure, and `UNION ALL`
combines the measures from all 5 files into one list.

For `dim_period`, `UNION` combines the date ranges from all files and removes
duplicates. `start_date::DATE` converts the text to a date.

### Step 5: Fact tables

```sql
CREATE TABLE fact_complications_deaths (
    facility_id  TEXT NOT NULL REFERENCES dim_hospital (facility_id),
    measure_id   TEXT NOT NULL REFERENCES dim_measure (measure_id),
    period_id    INTEGER REFERENCES dim_period (period_id),
    score        NUMERIC,
    ...
    PRIMARY KEY (facility_id, measure_id)
);
```

- Each row is one hospital's result on one measure.
- `REFERENCES dim_hospital (facility_id)` is a foreign key. The database checks that
  every facility ID in this table also exists in `dim_hospital`.
- `PRIMARY KEY (facility_id, measure_id)`: each hospital can have only one result per
  measure.
- `NUMERIC`: a number that can have decimals.

There are 5 fact tables: complications and deaths, infections, unplanned visits,
patient survey, and spending. With the 3 dimension tables, they form a star schema:
the fact tables are in the middle and each one links to the dimension tables.

The fact tables are filled like this:

```sql
INSERT INTO fact_complications_deaths
SELECT h.facility_id, r.measure_id, p.period_id,
       NULLIF(NULLIF(r.compared_to_national, 'Not Available'), ''),
       CASE WHEN r.score ~ '^-?[0-9.]+$' THEN r.score::NUMERIC END,
       ...
FROM raw_complications r
JOIN dim_hospital h ON h.facility_id = LPAD(r.facility_id, 6, '0')
LEFT JOIN dim_period p ON p.start_date = NULLIF(r.start_date, '')::DATE
                      AND p.end_date   = NULLIF(r.end_date, '')::DATE;
```

- `NULLIF(x, 'Not Available')`: returns NULL when the value is "Not Available". The
  second `NULLIF` does the same for empty text.
- `CASE WHEN r.score ~ '^-?[0-9.]+$' THEN r.score::NUMERIC END`: `~` compares the value
  with a pattern. This pattern allows only digits, a decimal point and a minus sign, so
  it checks whether the value is a number. Numbers are converted. Anything else, such
  as "Not Available" or "--", becomes NULL.
- `REPLACE(x, ',', '')` (used for counts): removes commas, so "1,204" becomes "1204".
- `JOIN dim_hospital h ON ...`: keeps only rows for hospitals that are in
  `dim_hospital`. This keeps the foreign keys valid.
- `LEFT JOIN dim_period p ON ...`: finds the period number for each date range.
  `LEFT JOIN` keeps the row even when no period matches.
- `r`, `h` and `p` are short names (aliases) for the tables.

### load_log table

```sql
INSERT INTO load_log (dataset_id, title, local_file, rows_loaded) VALUES
('xubh-q36u', 'Hospital General Information', '/Users/Shared/...csv',
 (SELECT COUNT(*) FROM raw_hospital_info)), ...
```

- One row per CMS file, with its ID, name, saved location and number of rows.
- `(SELECT COUNT(*) FROM raw_hospital_info)`: counts the rows in the raw table.
- `loaded_at TIMESTAMP DEFAULT now()`: saves the date and time of the load.

### Step 6: Load checks

- **6a. Rows in raw files vs rows loaded**: compares row counts before and after
  cleaning. Matching numbers mean no rows were lost.
- **6b. Rows with no score**: counts results that CMS reported as "Not Available".
  `SUM(CASE WHEN score IS NULL THEN 1 ELSE 0 END)` adds 1 for each missing score.
- **6c. Column data types**: lists every column that is not text, to show that numbers
  and dates have the correct types. `information_schema.columns` is a built-in table
  where PostgreSQL lists all columns.

### Step 7: Exploratory queries

```sql
\set ECHO all
\ir exploration.sql
\set ECHO none
```

- `\ir exploration.sql`: runs `exploration.sql` from the same folder.
- `ECHO all`: prints each query and its title above the result. `ECHO none` turns
  this off again.

The last line printed is `BUILD COMPLETE`.

---

## 2. exploration.sql

13 queries about the data. The file contains only SQL, so it also works in the Query
Tool: highlight one query and press F5.

| # | Question | SQL used |
|---|---|---|
| 1 | How many rows are in each table? | `COUNT(*)`, `UNION ALL` to combine the counts |
| 2 | How many measures are in each category? | `GROUP BY`, `COUNT` |
| 3 | How many hospitals are there by type and ownership, and what is their average rating? | `AVG`, `ROUND`, percent rated = rated / total x 100 |
| 4 | How many hospitals have each star rating? | `GROUP BY overall_rating` |
| 5 | What are the lowest, highest and average spending ratios? | `MIN`, `MAX`, `AVG` |
| 6 | Do hospitals with more stars spend more? | `JOIN` spending to hospitals, `GROUP BY` rating |
| 7 | Do low, average and high spending hospitals get different patient ratings? | `CASE` to put hospitals into 3 spending levels |
| 8 | Which ownership types have more death rates worse than the national rate? | `LIKE 'Worse%'` for text starting with "Worse" |
| 9 | What is the average infection ratio for each infection type? | `LIKE '%SIR'` for measure IDs ending in SIR |
| 10 | What are the spending and star rating by state? | `LEFT JOIN`, `HAVING` for states with 10 or more hospitals |
| 11 | Which 10 states have the highest heart failure readmission rate? | `ORDER BY ... DESC LIMIT 10` |
| 12 | Which date ranges does the data cover? | `UNION ALL` of all fact tables, `JOIN` to periods |
| 13 | Do the values for one hospital match medicare.gov? | `WHERE facility_id = '010001'` |

Terms in these queries:
- **Spending ratio (MSPB)**: Medicare spending per patient at a hospital compared with
  the national median. 1.00 is the median, 1.10 is 10% more and 0.90 is 10% less.
- **SIR (infection ratio)**: 1.0 means as many infections as expected. Lower is better.
- `HAVING`: a filter on groups, used after `GROUP BY`.
- `ROUND(x, 2)`: rounds to 2 decimal places.

---

## 3. metabase_setup.py

A Python script that sets up Metabase through the Metabase API, which lets a program
send commands to Metabase.

Steps:

1. Checks that Metabase is running at `http://localhost:3000`. If it is not, it asks
   you to run `docker start metabase`.
2. Logs in with your Metabase email and password.
3. Adds the database connection, the same as Admin settings > Databases > Add database:
   - host `host.docker.internal` (from inside Docker, this is the laptop itself)
   - port `5432` (the default PostgreSQL port)
   - database `hospital_quality`, user `postgres`, and the password you enter

   If the connection already exists, the script uses it.
4. Syncs the tables so Metabase can see all 9 tables.
5. Creates a collection (a folder) named "Group 6: Hospital Quality".
6. Creates 5 saved questions, each based on a SQL query: CMS files loaded, table sizes,
   hospitals by star rating (bar chart), spending by star rating (bar chart), and a
   sample of hospitals. Questions that already exist are updated.
7. Creates a dashboard with the 5 questions.
8. Prints the links to the dashboard and the collection.

The script can be run again at any time. Run it again after rebuilding the database.

Main parts of the code:
- `QUESTIONS = [...]`: the 5 questions, each with a name, chart type and SQL query.
- `class Metabase`: sends requests to Metabase and prints an error message if one fails.
- `main()`: runs the steps above in order.
- `getpass`: asks for passwords without showing them on the screen.

---

## 4. run.sh (optional)

Runs the build from Terminal instead of pgAdmin.

1. `cd "$(dirname "$0")"`: moves to the folder where the script is saved.
2. Looks for `psql`, the Terminal version of the PSQL Tool. On a Mac it is often not
   available by name, so the script checks the usual install folders.
3. If `psql` is not found, it prints instructions for using the PSQL Tool in pgAdmin.
4. Runs `create_and_load.sql` and saves the output in `build_log.txt`. `tee` shows the
   output on the screen and saves it to the file at the same time.

Run it with `./run.sh`. It asks for the postgres password.
