# Our scripts, explained in plain English

This guide walks through every file in the repo and what each part does. No database
background needed.

## Quick glossary

- **Database**: a collection of tables, like a workbook with many sheets.
- **Table**: one sheet of data, with rows and columns.
- **CSV file**: a plain-text spreadsheet. Each line is a row, commas separate the columns.
- **SQL**: the language we use to talk to the database.
- **Primary key (PK)**: a column whose value is unique for every row, like an ID number.
- **Foreign key (FK)**: a column that points to the primary key of another table. It makes
  sure the two tables line up (you can't have a score for a hospital that doesn't exist).
- **NULL**: "no value" or "unknown". Different from zero.
- **pgAdmin**: the app we use to look at and run things in PostgreSQL.
- **PSQL Tool**: a command window inside pgAdmin. It can run a whole script file at once.
- **Metabase**: a tool for making charts and dashboards from our database.
- **Docker**: runs Metabase inside a "container" on our laptop, so we don't install it directly.

## The files

| File | What it's for |
|---|---|
| `create_and_load.sql` | Builds the whole database from scratch |
| `exploration.sql` | 13 questions we ask the data (run automatically at the end of the build) |
| `metabase_setup.py` | Connects Metabase to our database and makes a starter dashboard |
| `run.sh` | Optional: runs `create_and_load.sql` from Terminal instead of pgAdmin |
| `README.md` | Project overview and how to run it |

---

## 1. create_and_load.sql

Think of this script as a recipe. It runs top to bottom, in 6 steps.

### Settings at the top

```sql
\set ON_ERROR_STOP on
\pset footer off
\pset pager off
```

- `ON_ERROR_STOP on`: if anything goes wrong, stop right there instead of carrying on
  with broken data.
- `footer off`: don't print "(5 rows)" under every result. Just keeps the output tidy.
- `pager off`: show all results at once instead of pausing with "(END)".

Lines starting with a backslash (`\`) are instructions for the PSQL Tool itself, not SQL.
That's why this script needs the PSQL Tool rather than the Query Tool.

### Step 1: Create the database

```sql
\c postgres
DROP DATABASE IF EXISTS hospital_quality WITH (FORCE);
CREATE DATABASE hospital_quality;
\c hospital_quality
SET datestyle = 'ISO, MDY';
```

- `\c postgres`: connect to the default database first (you can't delete a database
  while you're inside it).
- `DROP DATABASE IF EXISTS ...`: delete our old database if there is one, so every run
  starts fresh. `WITH (FORCE)` kicks out anything still connected to it, like Metabase.
- `CREATE DATABASE hospital_quality`: make a new, empty database.
- `\c hospital_quality`: move into the new database. Everything after this happens inside it.
- `SET datestyle = 'ISO, MDY'`: tells Postgres that dates like `07/01/2024` mean
  month/day/year (US style), which is how CMS writes them.

### Step 2: Raw tables

```sql
CREATE TEMP TABLE raw_hospital_info (
    facility_id TEXT, facility_name TEXT, address TEXT, ...
);
```

- We make 6 **temporary** tables, one for each CSV file. Temporary means they disappear
  automatically when the script finishes, so they never clutter the database.
- Every column is `TEXT` (plain text). CMS puts words like "Not Available" inside number
  columns, so if we tried to load them straight into number columns, the load would fail.
  Loading as text first, then cleaning, avoids that.
- The columns are listed in the exact order they appear in each CSV file.

### Step 3: Download and load the CMS files

```sql
COPY raw_hospital_info FROM PROGRAM
    'mkdir -p /Users/Shared/hospital_quality_data && cd /Users/Shared/hospital_quality_data
     && curl -sSfL -o Hospital_General_Information.csv "https://data.cms.gov/...xubh-q36u/..."
     && cat Hospital_General_Information.csv'
    WITH (FORMAT csv, HEADER true);
```

This one statement does four things, in order (`&&` means "and then, if that worked"):

1. `mkdir -p /Users/Shared/hospital_quality_data`: make the folder if it doesn't exist.
   We use `/Users/Shared` because every Mac has it and Postgres is allowed to write there.
2. `cd ...`: go into that folder.
3. `curl ... -o Hospital_General_Information.csv "https://..."`: download the file from
   the CMS website and save it. The link uses the dataset's permanent ID (`xubh-q36u`),
   so it keeps working when CMS updates the data every quarter.
4. `cat Hospital_General_Information.csv`: read the file out so `COPY` can load it.

- `COPY raw_hospital_info FROM PROGRAM ...`: put whatever that program outputs into the
  raw table.
- `FORMAT csv`: the data is comma-separated.
- `HEADER true`: skip the first line, because it has column names, not data.

The same pattern repeats for all 6 files. If a download fails (no internet), the script
stops with an error because of `ON_ERROR_STOP`.

### Step 4: Dimension tables (the "who, what, when")

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

- `dim_hospital` has one row per hospital. `facility_id` is the **primary key**, so no
  two hospitals can share an ID.
- `facility_id` and `zip_code` stay as text on purpose: they have leading zeros
  (`010001`) that would be lost if stored as numbers.
- `NOT NULL`: this column must always have a value.
- `CHAR(2)`: exactly 2 letters (state codes like `CA`).
- `BOOLEAN`: true or false.
- `SMALLINT CHECK (... BETWEEN 1 AND 5)`: a small whole number, and the database refuses
  anything outside 1 to 5 (star ratings).

We also make:
- `dim_measure`: one row per thing CMS measures (like "heart failure death rate"), with
  which category it belongs to.
- `dim_period`: one row per date range the measures cover. `SERIAL` means Postgres
  numbers the rows 1, 2, 3... automatically.

Then we fill them from the raw tables:

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

- `INSERT INTO ... SELECT ...`: copy rows from one table into another, cleaning them on the way.
- `LPAD(facility_id, 6, '0')`: pad the ID with zeros on the left to make it 6 characters.
  Some CMS files drop the leading zero (`10001` instead of `010001`).
- `CASE ... WHEN 'Yes' THEN TRUE ...`: turn the words Yes/No into true/false.
- `COALESCE(x = 'Y', FALSE)`: the birthing-friendly column is either "Y" or blank.
  This says "true if Y, otherwise false".
- `CASE WHEN rating IN ('1',...,'5') THEN rating::SMALLINT END`: only keep ratings that
  are 1 to 5. Anything else (like "Not Available") becomes NULL. `::SMALLINT` converts
  text to a number.

For `dim_measure`, `GROUP BY measure_id` gives one row per measure, and `UNION ALL` stacks
the measures from all 5 files into one list.

For `dim_period`, `UNION` stacks the date ranges from all files and removes duplicates.
`start_date::DATE` converts the text into a real date.

### Step 5: Fact tables (the actual measurements)

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

- Each row is **one hospital's result on one measure**.
- `REFERENCES dim_hospital (facility_id)`: this is a **foreign key**. The database checks
  that every hospital ID here exists in `dim_hospital`.
- `PRIMARY KEY (facility_id, measure_id)`: the combination of hospital + measure must be
  unique (a hospital can't have two results for the same measure).
- `NUMERIC`: a number that can have decimals.

We make 5 of these: complications/deaths, infections, unplanned visits, patient survey,
and spending. Together with the 3 dimension tables, this is our **star schema**: the
dimension tables sit around the fact tables like points of a star.

Filling them:

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

- `NULLIF(x, 'Not Available')`: if the value is "Not Available", make it NULL.
  Doing it twice also turns empty text into NULL.
- `CASE WHEN r.score ~ '^-?[0-9.]+$' THEN r.score::NUMERIC END`: `~` checks a pattern.
  This pattern means "only digits, a decimal point, and maybe a minus sign", in other
  words "looks like a number". If it does, convert it to a number. If not
  ("Not Available", "--"), it becomes NULL.
- `REPLACE(x, ',', '')` (used for counts): removes commas, so "1,204" becomes "1204".
- `JOIN dim_hospital h ON ...`: only keep rows for hospitals that exist in `dim_hospital`.
  This is what guarantees the foreign keys never fail.
- `LEFT JOIN dim_period p ON ...`: look up the period number for each row's date range.
  `LEFT` means keep the row even if no period matches.
- The letters `r`, `h`, `p` are short nicknames for the tables, so we don't have to type
  full names every time.

### load_log: a record of what was loaded

```sql
INSERT INTO load_log (dataset_id, title, local_file, rows_loaded) VALUES
('xubh-q36u', 'Hospital General Information', '/Users/Shared/...csv',
 (SELECT COUNT(*) FROM raw_hospital_info)), ...
```

- One row per CMS file: its ID, name, where it was saved, and how many rows it had.
- `(SELECT COUNT(*) FROM raw_hospital_info)`: counts the rows in the raw table.
- `loaded_at TIMESTAMP DEFAULT now()`: automatically records the date and time.

### Step 6: Load checks

- **6a. Rows in raw files vs rows loaded**: counts rows before and after cleaning. If the
  two numbers match, nothing got lost.
- **6b. Rows with no score**: how many results CMS reported as "Not Available".
  `SUM(CASE WHEN score IS NULL THEN 1 ELSE 0 END)` counts 1 for every missing score.
- **6c. Column data types**: lists every column that isn't plain text, to prove numbers
  and dates were stored with the right types. `information_schema.columns` is a built-in
  table where Postgres describes all columns.

### Step 7: Exploratory queries

```sql
\set ECHO all
\ir exploration.sql
\set ECHO none
```

- `\ir exploration.sql`: run the file `exploration.sql` from the same folder.
- `ECHO all`: print each query (with its title) above its result, so the output is easy
  to read. `ECHO none` turns that back off.

At the very end it prints `BUILD COMPLETE`.

---

## 2. exploration.sql

13 questions we ask the data. It's plain SQL, so it also works in the Query Tool
(highlight one query, press F5).

| # | Question | Key SQL used |
|---|---|---|
| 1 | How many rows are in each table? | `COUNT(*)`, `UNION ALL` stacks the counts into one list |
| 2 | How many measures are in each category? | `GROUP BY` groups rows, `COUNT` counts each group |
| 3 | How many hospitals of each type and ownership, and their average rating? | `AVG`, `ROUND`, percent rated = rated / total × 100 |
| 4 | How many hospitals got each star rating? | `GROUP BY overall_rating` |
| 5 | What's the lowest, highest and average spending ratio? | `MIN`, `MAX`, `AVG` |
| 6 | Do higher-rated hospitals spend more? | `JOIN` spending to hospitals, `GROUP BY` rating |
| 7 | Do low, average and high spenders get different patient ratings? | `CASE` sorts hospitals into 3 spending levels |
| 8 | Which ownership types have more "worse than national" death rates? | `LIKE 'Worse%'` finds text starting with "Worse" |
| 9 | Average infection ratio for each infection type | `LIKE '%SIR'` finds measure IDs ending in SIR |
| 10 | Spending and star rating by state | `LEFT JOIN`, `HAVING` keeps states with 10+ hospitals |
| 11 | Top 10 states for heart failure readmissions | `ORDER BY ... DESC LIMIT 10` |
| 12 | What date ranges does the data cover? | `UNION ALL` of all fact tables, `JOIN` to periods |
| 13 | Spot check one hospital against medicare.gov | `WHERE facility_id = '010001'` |

A few terms that show up:
- **Spending ratio (MSPB)**: how much Medicare spends per patient at a hospital compared
  to the national middle. 1.00 = average, 1.10 = 10% more, 0.90 = 10% less.
- **SIR (infection ratio)**: 1.0 = as many infections as expected. Lower is better.
- `HAVING` is like `WHERE`, but for groups (after `GROUP BY`).
- `ROUND(x, 2)`: round to 2 decimal places.

---

## 3. metabase_setup.py

A Python script that clicks through Metabase's setup for us, using Metabase's API
(a way for programs to talk to Metabase directly).

What it does, in order:

1. **Checks Metabase is running** at `http://localhost:3000`. If not, it tells you to run
   `docker start metabase`.
2. **Logs in** with your Metabase email and password (it asks you for them).
3. **Adds the database connection**, the same as Admin settings > Databases > Add database,
   with:
   - host `host.docker.internal` (from inside Docker, this means "my laptop")
   - port `5432` (the usual Postgres port)
   - database `hospital_quality`, user `postgres`, and the password you type in

   If the connection already exists, it reuses it.
4. **Syncs the tables** so Metabase knows about all 9 tables.
5. **Makes a collection** (a folder) called "Group 6: Hospital Quality".
6. **Creates 5 saved questions** (each is a SQL query):
   CMS files loaded, table sizes, hospitals by star rating (bar chart),
   spending by star rating (bar chart), and a sample of hospitals.
   If a question already exists, it updates it instead of making a duplicate.
7. **Creates a dashboard** with all 5 questions on one page.
8. **Prints the links** to the dashboard and collection.

Safe to run as many times as you want. Run it again after rebuilding the database.

The main parts of the code:
- `QUESTIONS = [...]`: the list of the 5 questions: name, chart type, and SQL.
- `class Metabase`: a small helper that sends requests to Metabase and shows a clear
  message if something fails.
- `main()`: the steps above, one after another.
- `getpass`: asks for passwords without showing them on screen.

---

## 4. run.sh (optional)

A shortcut to build the database from Terminal instead of pgAdmin.

1. `cd "$(dirname "$0")"`: go to the folder the script is in.
2. Looks for `psql` (the command-line version of the PSQL Tool). On Macs it's often not
   set up to type directly, so it checks the usual install locations.
3. If it can't find it, it tells you to use pgAdmin's PSQL Tool instead.
4. Runs `create_and_load.sql` and saves all the output into `build_log.txt`
   (`tee` shows it on screen and saves it at the same time).

Run it with `./run.sh`. It asks for the postgres password.
