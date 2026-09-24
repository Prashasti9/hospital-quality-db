# metabase_setup.py
# DSAI-691 Group 6: U.S. Hospital Quality & Cost
#
# Connects Metabase to the hospital_quality database and creates 5 questions
# and a dashboard, using the Metabase REST API.
#
# Before running:
#   1. Metabase is running in Docker (docker start metabase)
#   2. You have created your Metabase account at http://localhost:3000
#   3. create_and_load.sql has built the hospital_quality database
#
# Run from the repo folder:  python3 metabase/metabase_setup.py
# It can be run again. Existing items are reused or updated, not duplicated.

import getpass
import time

import requests

METABASE_URL = "http://localhost:3000"
DB_NAME = "hospital_quality"
DB_DISPLAY_NAME = "Hospital Quality (Group 6)"
COLLECTION_NAME = "Group 6: Hospital Quality"
DASHBOARD_NAME = "Task 2: Data loaded and connected"

# The 5 saved questions: name, chart type, chart settings, size on the dashboard, SQL
QUESTIONS = [
    {
        "name": "1. CMS files loaded (row counts)",
        "display": "table",
        "settings": {},
        "width": 12, "height": 6,
        "sql": """SELECT dataset_id, title, rows_loaded, loaded_at
FROM load_log
ORDER BY dataset_id""",
    },
    {
        "name": "2. Star schema table sizes",
        "display": "table",
        "settings": {},
        "width": 12, "height": 6,
        "sql": """SELECT 'dim_hospital' AS table_name, COUNT(*) AS row_count FROM dim_hospital
UNION ALL SELECT 'dim_measure', COUNT(*) FROM dim_measure
UNION ALL SELECT 'dim_period', COUNT(*) FROM dim_period
UNION ALL SELECT 'fact_complications_deaths', COUNT(*) FROM fact_complications_deaths
UNION ALL SELECT 'fact_infections', COUNT(*) FROM fact_infections
UNION ALL SELECT 'fact_unplanned_visits', COUNT(*) FROM fact_unplanned_visits
UNION ALL SELECT 'fact_patient_survey', COUNT(*) FROM fact_patient_survey
UNION ALL SELECT 'fact_spending', COUNT(*) FROM fact_spending""",
    },
    {
        "name": "3. Hospitals by overall star rating",
        "display": "bar",
        "settings": {"graph.dimensions": ["star_rating"], "graph.metrics": ["hospitals"]},
        "width": 12, "height": 6,
        "sql": """SELECT COALESCE(overall_rating::TEXT || ' stars', 'Not rated') AS star_rating,
       COUNT(*) AS hospitals
FROM dim_hospital
GROUP BY overall_rating
ORDER BY overall_rating NULLS LAST""",
    },
    {
        "name": "4. Average Medicare spending ratio by star rating",
        "display": "bar",
        "settings": {"graph.dimensions": ["star_rating"], "graph.metrics": ["avg_spending_ratio"]},
        "width": 12, "height": 6,
        "sql": """SELECT h.overall_rating::TEXT || ' stars' AS star_rating,
       ROUND(AVG(s.mspb_ratio), 3) AS avg_spending_ratio,
       COUNT(*) AS hospitals
FROM fact_spending s
JOIN dim_hospital h ON h.facility_id = s.facility_id
WHERE h.overall_rating IS NOT NULL AND s.mspb_ratio IS NOT NULL
GROUP BY h.overall_rating
ORDER BY h.overall_rating""",
    },
    {
        "name": "5. Sample of hospitals (real rows)",
        "display": "table",
        "settings": {},
        "width": 24, "height": 8,
        "sql": """SELECT facility_id, facility_name, city_town, state, hospital_type,
       hospital_ownership, overall_rating
FROM dim_hospital
ORDER BY state, facility_name
LIMIT 200""",
    },
]

# One session for all requests. After login it carries the session token.
session = requests.Session()


def api(method, path, body=None):
    """Send one request to the Metabase API and return the JSON response."""
    response = session.request(method, METABASE_URL + path, json=body, timeout=120)
    if response.status_code >= 400:
        print(f"Metabase API error {response.status_code} on {method} {path}:")
        print(response.text[:500])
        raise SystemExit(1)
    return response.json() if response.text.strip() else {}


def as_list(result):
    """Some Metabase versions return a list, others return {'data': [...]}."""
    if isinstance(result, dict) and "data" in result:
        return result["data"]
    return result


def log_in():
    email = input("Metabase email: ").strip()
    password = getpass.getpass("Metabase password: ")
    token = api("POST", "/api/session", {"username": email, "password": password})["id"]
    session.headers["X-Metabase-Session"] = token
    print("Logged in to Metabase.")


def get_or_add_database():
    for db in as_list(api("GET", "/api/database")):
        if db.get("engine") == "postgres" and db.get("details", {}).get("dbname") == DB_NAME:
            print(f"Database connection already exists (id {db['id']}).")
            return db["id"]

    pg_password = getpass.getpass("Postgres password (user postgres): ")
    details = {
        "host": "host.docker.internal",   # from inside Docker, this means our laptop
        "port": 5432,
        "dbname": DB_NAME,
        "user": "postgres",
        "password": pg_password,
        "ssl": False,
    }
    db = api("POST", "/api/database",
             {"engine": "postgres", "name": DB_DISPLAY_NAME, "details": details})
    print(f"Connected Metabase to {DB_NAME} (id {db['id']}).")
    return db["id"]


def sync_tables(db_id):
    api("POST", f"/api/database/{db_id}/sync_schema")
    print("Syncing tables...")
    time.sleep(15)
    tables = [t["name"] for t in api("GET", f"/api/database/{db_id}/metadata")["tables"]]
    print(f"Metabase sees {len(tables)} tables: {', '.join(sorted(tables))}")


def get_or_create_collection():
    for c in as_list(api("GET", "/api/collection")):
        if c.get("name") == COLLECTION_NAME and not c.get("archived"):
            return c["id"]
    return api("POST", "/api/collection", {"name": COLLECTION_NAME, "color": "#509EE3"})["id"]


def save_questions(db_id, collection_id):
    items = as_list(api("GET", f"/api/collection/{collection_id}/items?models=card"))
    existing = {item["name"]: item["id"] for item in items}

    card_ids = []
    for q in QUESTIONS:
        card = {
            "name": q["name"],
            "display": q["display"],
            "visualization_settings": q["settings"],
            "collection_id": collection_id,
            "dataset_query": {
                "type": "native",
                "database": db_id,
                "native": {"query": q["sql"]},
            },
        }
        if q["name"] in existing:
            card_id = existing[q["name"]]
            api("PUT", f"/api/card/{card_id}", card)
            print(f"Updated question: {q['name']}")
        else:
            card_id = api("POST", "/api/card", card)["id"]
            print(f"Created question: {q['name']}")
        card_ids.append(card_id)
    return card_ids


def create_dashboard(collection_id, card_ids):
    items = as_list(api("GET", f"/api/collection/{collection_id}/items?models=dashboard"))
    for item in items:
        if item["name"] == DASHBOARD_NAME:
            print(f"Dashboard already exists: {DASHBOARD_NAME}")
            return item["id"]

    dashboard_id = api("POST", "/api/dashboard",
                       {"name": DASHBOARD_NAME, "collection_id": collection_id})["id"]

    # Place the questions two per row (the dashboard grid is 24 units wide)
    dashcards = []
    row, col = 0, 0
    for i, (card_id, q) in enumerate(zip(card_ids, QUESTIONS)):
        if col + q["width"] > 24:
            row, col = row + q["height"], 0
        dashcards.append({"id": -(i + 1), "card_id": card_id,
                          "row": row, "col": col,
                          "size_x": q["width"], "size_y": q["height"],
                          "parameter_mappings": [], "visualization_settings": {}})
        col += q["width"]

    api("PUT", f"/api/dashboard/{dashboard_id}", {"dashcards": dashcards})
    print(f"Created dashboard: {DASHBOARD_NAME}")
    return dashboard_id


def main():
    try:
        requests.get(METABASE_URL + "/api/health", timeout=10)
    except requests.exceptions.ConnectionError:
        print(f"Cannot reach Metabase at {METABASE_URL}.")
        print("Start it with: docker start metabase (then wait about a minute)")
        raise SystemExit(1)

    log_in()
    db_id = get_or_add_database()
    sync_tables(db_id)
    collection_id = get_or_create_collection()
    card_ids = save_questions(db_id, collection_id)
    dashboard_id = create_dashboard(collection_id, card_ids)

    print(f"\nDashboard:  {METABASE_URL}/dashboard/{dashboard_id}")
    print(f"Collection: {METABASE_URL}/collection/{collection_id}")
    print("Done.")


if __name__ == "__main__":
    main()
