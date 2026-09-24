# Metabase Setup Guide

This guide explains how to set up Metabase in Docker and what `metabase_setup.py` does.
The SQL scripts are explained in `SQL_EXPLAINED.md` in the main folder.

## Terms used

- **Metabase**: a website that runs on your laptop and makes charts and dashboards
  from a database.
- **Docker**: a program that runs Metabase inside a container, so Metabase does not
  need to be installed directly.
- **Container**: a small, separate environment that Docker runs. Ours is named `metabase`.
- **API**: a way for a program to send commands to another program over HTTP.
- **JSON**: the text format used to send data to and from an API.
- **Session token**: a code Metabase gives you after login. It is sent with every
  request to prove you are logged in.

## First-time setup (if you have never run Metabase in Docker)

1. Install **Docker Desktop** from https://www.docker.com/products/docker-desktop/
   (choose Apple chip or Intel chip to match your Mac). Open it and wait until it says
   it is running.
2. Create and start the Metabase container. In Terminal:
   ```
   docker run -d --name metabase -p 3000:3000 -v metabase-data:/metabase-data -e MB_DB_FILE=/metabase-data/metabase.db metabase/metabase:latest
   ```
   - `-d`: runs in the background.
   - `--name metabase`: names the container `metabase`.
   - `-p 3000:3000`: makes Metabase available at `http://localhost:3000`.
   - `-v metabase-data:/metabase-data` and `MB_DB_FILE=...`: save your Metabase
     account, questions and dashboards, so they are kept if the container is removed.
3. Wait about 2 minutes, then open http://localhost:3000 in your browser.
4. Create your Metabase account (name, email, password). When it asks you to add
   data, you can skip it. The script adds the database connection.

After this, you only need `docker start metabase` each time. Docker Desktop must be
open first.

## Connecting Metabase to the database

1. Build the database first (see `README.md`).
2. Check that the `requests` library is installed (it comes with Anaconda):
   ```
   pip3 install requests
   ```
3. Run the script from the repo folder:
   ```
   cd ~/hospital-quality-db
   python3 metabase/metabase_setup.py
   ```
4. Enter your Metabase email and password, then your Postgres password.
5. Open the dashboard link that it prints.

Run the script again whenever you rebuild the database, so Metabase reads the new tables.

### If something goes wrong

- **Cannot reach Metabase**: open Docker Desktop, run `docker start metabase`, wait a
  minute and try again.
- **Metabase API error 401**: the Metabase email or password is wrong.
- **Error about the database connection, "Connection refused" or "pg_hba.conf"**:
  Postgres is refusing connections from Docker. In the pgAdmin Query Tool, run
  `SHOW hba_file;` to find the file, open it in a text editor and add this line at the end:
  ```
  host    all    all    0.0.0.0/0    scram-sha-256
  ```
  Then run `SHOW config_file;`, open that file and set `listen_addresses = '*'`.
  Restart your Mac (or restart Postgres) and run the script again.

---

## metabase_setup.py

A Python script that sets up Metabase through the Metabase REST API, using the
`requests` library. It is a client for Metabase's API, the same idea as calling a
FastAPI endpoint. Everything it does can also be done by hand in the Metabase website. The
script does the same steps automatically.

Run it from the repo folder:

```
python3 metabase/metabase_setup.py
```

### API calls it makes, in order

| Step | Request | What it does |
|---|---|---|
| Check Metabase is up | `GET /api/health` | If Metabase is not running, it asks you to run `docker start metabase` |
| Log in | `POST /api/session` | Sends your email and password and gets a session token |
| Add the database | `POST /api/database` | Sends the Postgres connection details as JSON |
| Sync tables | `POST /api/database/{id}/sync_schema` | Tells Metabase to read the tables |
| Make a folder | `POST /api/collection` | Creates the "Group 6: Hospital Quality" collection |
| Save questions | `POST /api/card` (or `PUT` to update) | Saves each SQL query as a question |
| Make a dashboard | `POST /api/dashboard`, then `PUT /api/dashboard/{id}` | Creates the dashboard and places the 5 questions on it |

### Imports and settings

```python
import getpass
import time
import requests

METABASE_URL = "http://localhost:3000"
DB_NAME = "hospital_quality"
DB_DISPLAY_NAME = "Hospital Quality (Group 6)"
COLLECTION_NAME = "Group 6: Hospital Quality"
DASHBOARD_NAME = "Task 2: Data loaded and connected"
```

- `getpass`: asks for passwords without showing them on the screen.
- `time`: used to wait a few seconds while Metabase reads the tables.
- `requests`: sends HTTP requests (GET, POST, PUT) to Metabase.
- The capital-letter names are settings used later: where Metabase runs, the name of
  our database, and the names to use for the connection, folder and dashboard.

### The 5 questions

```python
QUESTIONS = [
    {
        "name": "3. Hospitals by overall star rating",
        "display": "bar",
        "settings": {"graph.dimensions": ["star_rating"], "graph.metrics": ["hospitals"]},
        "width": 12, "height": 6,
        "sql": """SELECT ... FROM dim_hospital GROUP BY overall_rating ...""",
    },
    ...
]
```

- `QUESTIONS` is a list of dictionaries, one per question.
- `name`: the title shown in Metabase.
- `display`: the chart type. `table` shows rows, `bar` shows a bar chart.
- `settings`: for bar charts, which column goes on the x-axis (`graph.dimensions`) and
  which goes on the y-axis (`graph.metrics`).
- `width` and `height`: the size of the card on the dashboard. The dashboard is 24
  units wide, so width 12 means half the page.
- `sql`: the SQL query. Triple quotes (`"""`) allow the query to span several lines.

### Session and the api() helper

```python
session = requests.Session()

def api(method, path, body=None):
    response = session.request(method, METABASE_URL + path, json=body, timeout=120)
    if response.status_code >= 400:
        print(f"Metabase API error {response.status_code} on {method} {path}:")
        print(response.text[:500])
        raise SystemExit(1)
    return response.json() if response.text.strip() else {}
```

- `requests.Session()`: keeps settings between requests. After login we add the token
  to it once, and every later request sends it automatically.
- `api()` is used for every call so the same code is not repeated:
  - `method` is "GET", "POST" or "PUT", and `path` is the endpoint, such as `/api/card`.
  - `json=body` sends the Python dictionary as JSON.
  - `timeout=120` stops waiting after 120 seconds.
  - A status code of 400 or higher means an error (for example 401 for a wrong
    password). The script prints the message from Metabase and stops.
  - Otherwise it returns the response as a Python dictionary or list.

```python
def as_list(result):
    if isinstance(result, dict) and "data" in result:
        return result["data"]
    return result
```

- Some Metabase versions return a plain list and others return `{"data": [...]}`.
  This function always gives back a plain list.

### log_in()

```python
def log_in():
    email = input("Metabase email: ").strip()
    password = getpass.getpass("Metabase password: ")
    token = api("POST", "/api/session", {"username": email, "password": password})["id"]
    session.headers["X-Metabase-Session"] = token
```

- Asks for your Metabase email and password.
- `POST /api/session` logs in. Metabase returns a session token in the `id` field.
- The token is stored in the session headers, so all later requests are logged in.
  This is the same idea as sending a token to a protected FastAPI endpoint.

### get_or_add_database()

```python
def get_or_add_database():
    for db in as_list(api("GET", "/api/database")):
        if db.get("engine") == "postgres" and db.get("details", {}).get("dbname") == DB_NAME:
            return db["id"]

    pg_password = getpass.getpass("Postgres password (user postgres): ")
    details = {
        "host": "host.docker.internal",
        "port": 5432,
        "dbname": DB_NAME,
        "user": "postgres",
        "password": pg_password,
        "ssl": False,
    }
    db = api("POST", "/api/database",
             {"engine": "postgres", "name": DB_DISPLAY_NAME, "details": details})
    return db["id"]
```

- `GET /api/database` lists the databases Metabase already knows. If one is a
  Postgres connection to `hospital_quality`, the script reuses it and returns its id.
- If not, it asks for the Postgres password and sends the connection details with
  `POST /api/database`. This is the same form as Admin settings > Databases > Add database.
- `host.docker.internal`: Metabase runs inside Docker, and from inside Docker this name
  means our laptop, where Postgres runs. `localhost` would point to the container itself.
- `db.get(...)` is used instead of `db[...]` so the code does not crash if a field is missing.

### sync_tables()

```python
def sync_tables(db_id):
    api("POST", f"/api/database/{db_id}/sync_schema")
    time.sleep(15)
    tables = [t["name"] for t in api("GET", f"/api/database/{db_id}/metadata")["tables"]]
    print(f"Metabase sees {len(tables)} tables: ...")
```

- `sync_schema` tells Metabase to read the list of tables and columns again. This is
  needed after rebuilding the database.
- `time.sleep(15)` waits 15 seconds while Metabase does this.
- `GET .../metadata` returns the tables Metabase found. The list comprehension
  `[t["name"] for t in ...]` keeps just the table names, and the script prints them.

### get_or_create_collection()

```python
def get_or_create_collection():
    for c in as_list(api("GET", "/api/collection")):
        if c.get("name") == COLLECTION_NAME and not c.get("archived"):
            return c["id"]
    return api("POST", "/api/collection", {"name": COLLECTION_NAME, "color": "#509EE3"})["id"]
```

- A collection is a folder in Metabase.
- The script looks for a folder called "Group 6: Hospital Quality" that is not in the
  trash (`archived`). If it exists, it is reused. If not, `POST /api/collection` creates it.

### save_questions()

```python
def save_questions(db_id, collection_id):
    items = as_list(api("GET", f"/api/collection/{collection_id}/items?models=card"))
    existing = {item["name"]: item["id"] for item in items}

    for q in QUESTIONS:
        card = {
            "name": q["name"],
            "display": q["display"],
            "visualization_settings": q["settings"],
            "collection_id": collection_id,
            "dataset_query": {"type": "native", "database": db_id,
                              "native": {"query": q["sql"]}},
        }
        if q["name"] in existing:
            api("PUT", f"/api/card/{existing[q['name']]}", card)
        else:
            api("POST", "/api/card", card)
```

- Metabase calls a saved question a "card".
- First it gets the questions already in the folder and builds a dictionary of
  name to id (`existing`).
- For each question it builds the JSON Metabase expects:
  - `"type": "native"` means a SQL query (not a question built with Metabase's editor).
  - `"database": db_id` says which database to run it on.
  - `"query": q["sql"]` is the SQL text.
- If a question with the same name exists, `PUT /api/card/{id}` updates it. Otherwise
  `POST /api/card` creates it. This is why running the script twice does not create copies.
- The function returns the list of card ids for the dashboard.

### create_dashboard()

```python
def create_dashboard(collection_id, card_ids):
    ...
    dashboard_id = api("POST", "/api/dashboard",
                       {"name": DASHBOARD_NAME, "collection_id": collection_id})["id"]

    dashcards = []
    row, col = 0, 0
    for i, (card_id, q) in enumerate(zip(card_ids, QUESTIONS)):
        if col + q["width"] > 24:
            row, col = row + q["height"], 0
        dashcards.append({"id": -(i + 1), "card_id": card_id,
                          "row": row, "col": col,
                          "size_x": q["width"], "size_y": q["height"], ...})
        col += q["width"]

    api("PUT", f"/api/dashboard/{dashboard_id}", {"dashcards": dashcards})
```

- If a dashboard with this name already exists in the folder, it is left as it is.
- `POST /api/dashboard` creates an empty dashboard.
- The loop places each question on the dashboard grid:
  - `row` and `col` are the position. `col` moves right by the card width.
  - If the next card does not fit in the 24-unit row, it moves down to a new row.
  - `zip(card_ids, QUESTIONS)` pairs each card id with its question, and `enumerate`
    adds a counter `i`.
  - `"id": -(i + 1)` gives each new card a temporary negative id, which is how the
    Metabase API recognizes cards that are new.
- `PUT /api/dashboard/{id}` saves all the cards onto the dashboard in one request.

### main()

```python
def main():
    try:
        requests.get(METABASE_URL + "/api/health", timeout=10)
    except requests.exceptions.ConnectionError:
        print("Cannot reach Metabase ... Start it with: docker start metabase")
        raise SystemExit(1)

    log_in()
    db_id = get_or_add_database()
    sync_tables(db_id)
    collection_id = get_or_create_collection()
    card_ids = save_questions(db_id, collection_id)
    dashboard_id = create_dashboard(collection_id, card_ids)
    print(f"Dashboard:  {METABASE_URL}/dashboard/{dashboard_id}")

if __name__ == "__main__":
    main()
```

- First it checks that Metabase answers. If Docker or Metabase is not running, it
  prints how to start it and stops.
- Then it calls the functions in order. Each one passes its result (like `db_id`) to
  the next.
- At the end it prints the link to the dashboard.
- `if __name__ == "__main__":` means `main()` runs when the file is run directly with
  `python3`, but not if another file imports it.
