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
COLLECTION_NAME = "Davey Grimes - Spending vs Quality"
DASHBOARD_NAME  = "Does spending buy better hospital care?"

# The 5 saved questions: name, chart type, chart settings, size on the dashboard, SQL
QUESTIONS = [

    {
        "name": "1. Spending vs quality by state",
        "display": "scatter",
        "settings": {
            "graph.dimensions": ["avg_spending_ratio"],
            "graph.metrics": ["avg_star_rating"],
            "scatter.bubble": "hospitals",
            "graph.x_axis.title_text": "Avg spending ratio (1.0 = national avg)",
            "graph.y_axis.title_text": "Avg overall star rating",
        },
        "width": 12, "height": 7,
        "sql": """
SELECT h.state, COUNT(s.mspb_ratio) AS hospitals, ROUND(AVG(s.mspb_ratio), 3) AS avg_spending_ratio, ROUND(AVG(h.overall_rating), 2) AS avg_star_rating
FROM dim_hospital h
JOIN fact_spending s ON s.facility_id = h.facility_id
WHERE s.mspb_ratio IS NOT NULL
GROUP BY h.state
HAVING COUNT(s.mspb_ratio) >= 10
ORDER BY avg_spending_ratio DESC
""",
    },

    {
        "name": "2. Rating and spending by ownership",
        "display": "combo",
        "settings": {
            "graph.dimensions": ["hospital_ownership"],
            "graph.metrics": ["avg_star_rating", "avg_spending_ratio"],
            "series_settings": {
                "avg_star_rating":    {"display": "bar",  "axis": "left"},
                "avg_spending_ratio": {"display": "line", "axis": "right"},
            },
            "graph.y_axis.title_text": "Avg overall star rating",
        },
        "width": 12, "height": 7,
        "sql": """
SELECT h.hospital_ownership, COUNT(*) AS hospitals, ROUND(AVG(h.overall_rating), 2) AS avg_star_rating, ROUND(AVG(s.mspb_ratio), 3) AS avg_spending_ratio
FROM dim_hospital h
LEFT JOIN fact_spending s ON s.facility_id = h.facility_id
WHERE h.hospital_type = 'Acute Care Hospitals'
GROUP BY h.hospital_ownership
HAVING COUNT(*) >= 20
ORDER BY avg_star_rating DESC
""",
    },

    {
        "name": "3. Share of top-rated hospitals by spending level",
        "display": "bar",
        "settings": {
            "graph.dimensions": ["spending_level"],
            "graph.metrics": ["pct_top_rated"],
            "graph.y_axis.title_text": "% of hospitals rated 4-5 stars",
        },
        "width": 8, "height": 7,
        "sql": """
SELECT CASE WHEN s.mspb_ratio < 0.95 THEN '1. Low (below 0.95)' WHEN s.mspb_ratio <= 1.05 THEN '2. Average (0.95 to 1.05)'
ELSE '3. High (above 1.05)' END AS spending_level, COUNT(h.overall_rating) AS rated_hospitals, SUM(CASE WHEN h.overall_rating >= 4 THEN 1 ELSE 0 END) AS top_rated,
ROUND(100.0 * SUM(CASE WHEN h.overall_rating >= 4 THEN 1 ELSE 0 END) / COUNT(h.overall_rating), 1) AS pct_top_rated
FROM fact_spending s
JOIN dim_hospital h ON h.facility_id = s.facility_id
WHERE s.mspb_ratio IS NOT NULL
AND h.overall_rating IS NOT NULL
GROUP BY spending_level
ORDER BY spending_level
""",
    },

    {
        "name": "4. Infection rate (SIR) by spending level",
        "display": "bar",
        "settings": {
            "graph.dimensions": ["spending_level"],
            "graph.metrics": ["avg_infection_sir"],
            "graph.y_axis.auto_range": False,
            "graph.y_axis.min": 0.4,
            "graph.y_axis.max": 0.6,
            "graph.y_axis.title_text": "Avg SIR (lower = fewer infections)",
        },
        "width": 8, "height": 7,
        "sql": """
WITH hosp_sir AS (
    SELECT f.facility_id, AVG(f.score) AS avg_sir
    FROM fact_infections f
    WHERE f.measure_id LIKE '%SIR'
    AND f.score IS NOT NULL
    GROUP BY f.facility_id
)
SELECT CASE WHEN s.mspb_ratio <  0.95 THEN '1. Low (below 0.95)' WHEN s.mspb_ratio <= 1.05 THEN '2. Average (0.95 to 1.05)'
ELSE '3. High (above 1.05)' END AS spending_level, COUNT(*) AS hospitals, ROUND(AVG(hs.avg_sir), 3)  AS avg_infection_sir
FROM fact_spending s
JOIN hosp_sir hs ON hs.facility_id = s.facility_id
WHERE s.mspb_ratio IS NOT NULL
GROUP BY spending_level
ORDER BY spending_level
""",
    },

    {
        "name": "5. Heart-failure readmission by spending level",
        "display": "bar",
        "settings": {
            "graph.dimensions": ["spending_level"],
            "graph.metrics": ["avg_hf_readmission_pct"],
            "graph.y_axis.auto_range": False,
            "graph.y_axis.min": 20,
            "graph.y_axis.max": 23,
            "graph.y_axis.title_text": "Avg 30-day HF readmission %",
        },
        "width": 8, "height": 7,
        "sql": """
SELECT CASE WHEN s.mspb_ratio <  0.95 THEN '1. Low (below 0.95)' WHEN s.mspb_ratio <= 1.05 THEN '2. Average (0.95 to 1.05)'
ELSE '3. High (above 1.05)' END AS spending_level, COUNT(f.score) AS hospitals, ROUND(AVG(f.score), 2) AS avg_hf_readmission_pct
FROM fact_spending s
JOIN fact_unplanned_visits f ON f.facility_id = s.facility_id
WHERE f.measure_id = 'READM_30_HF'
AND s.mspb_ratio IS NOT NULL
AND f.score IS NOT NULL
GROUP BY spending_level
ORDER BY spending_level
""",
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
