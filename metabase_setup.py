#!/usr/bin/env python3
"""
Connect Metabase to the hospital_quality database and create starter questions
and a dashboard, using Metabase's REST API. Safe to run again: it reuses the
database connection, collection, questions and dashboard if they already exist.

Before running:
  1. Metabase is running in Docker (docker start metabase) at http://localhost:3000
  2. You have finished Metabase's first-time setup and have an admin email/password
  3. create_and_load.sql has built the hospital_quality database

Run:  python3 metabase_setup.py
It asks for your Metabase login and your Postgres password. Standard library only.

Optional environment variables: MB_URL, MB_EMAIL, MB_PASSWORD,
PG_HOST (default host.docker.internal), PG_PORT, PG_USER (default postgres), PG_PASSWORD
"""
import getpass
import json
import os
import sys
import time
import urllib.error
import urllib.request

MB_URL = os.environ.get("MB_URL", "http://localhost:3000").rstrip("/")
DB_DISPLAY_NAME = "Hospital Quality (Group 6)"
DB_NAME = "hospital_quality"
COLLECTION_NAME = "Group 6: Hospital Quality"
DASHBOARD_NAME = "Task 2: Data loaded and connected"

QUESTIONS = [
    {
        "name": "1. CMS files loaded (row counts)",
        "display": "table",
        "sql": """SELECT dataset_id, title, cms_released, rows_loaded, loaded_at
FROM load_log
ORDER BY dataset_id""",
        "viz": {},
        "size": (12, 6),
    },
    {
        "name": "2. Star schema table sizes",
        "display": "table",
        "sql": """SELECT 'dim_hospital' AS table_name, COUNT(*) AS row_count FROM dim_hospital
UNION ALL SELECT 'dim_measure', COUNT(*) FROM dim_measure
UNION ALL SELECT 'dim_period', COUNT(*) FROM dim_period
UNION ALL SELECT 'fact_complications_deaths', COUNT(*) FROM fact_complications_deaths
UNION ALL SELECT 'fact_infections', COUNT(*) FROM fact_infections
UNION ALL SELECT 'fact_unplanned_visits', COUNT(*) FROM fact_unplanned_visits
UNION ALL SELECT 'fact_patient_survey', COUNT(*) FROM fact_patient_survey
UNION ALL SELECT 'fact_spending', COUNT(*) FROM fact_spending""",
        "viz": {},
        "size": (12, 6),
    },
    {
        "name": "3. Hospitals by overall star rating",
        "display": "bar",
        "sql": """SELECT COALESCE(overall_rating::TEXT || ' stars', 'Not rated') AS star_rating,
       COUNT(*) AS hospitals
FROM dim_hospital
GROUP BY overall_rating
ORDER BY overall_rating NULLS LAST""",
        "viz": {"graph.dimensions": ["star_rating"], "graph.metrics": ["hospitals"]},
        "size": (12, 6),
    },
    {
        "name": "4. Average Medicare spending ratio by star rating",
        "display": "bar",
        "sql": """SELECT h.overall_rating::TEXT || ' stars' AS star_rating,
       ROUND(AVG(s.mspb_ratio), 3) AS avg_spending_ratio,
       COUNT(*) AS hospitals
FROM fact_spending s
JOIN dim_hospital h USING (facility_id)
WHERE h.overall_rating IS NOT NULL AND s.mspb_ratio IS NOT NULL
GROUP BY h.overall_rating
ORDER BY h.overall_rating""",
        "viz": {"graph.dimensions": ["star_rating"], "graph.metrics": ["avg_spending_ratio"]},
        "size": (12, 6),
    },
    {
        "name": "5. Sample of hospitals (real rows)",
        "display": "table",
        "sql": """SELECT facility_id, facility_name, city_town, state, hospital_type,
       hospital_ownership, overall_rating
FROM dim_hospital
ORDER BY state, facility_name
LIMIT 200""",
        "viz": {},
        "size": (24, 8),
    },
]


class Metabase:
    def __init__(self, base):
        self.base = base
        self.token = None

    def call(self, method, path, body=None, ok_errors=()):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(self.base + path, data=data, method=method)
        req.add_header("Content-Type", "application/json")
        if self.token:
            req.add_header("X-Metabase-Session", self.token)
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                raw = resp.read().decode()
                return json.loads(raw) if raw.strip() else {}
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")[:600]
            if e.code in ok_errors:
                return None
            raise SystemExit(f"\nMetabase API error {e.code} on {method} {path}:\n{detail}")
        except urllib.error.URLError as e:
            raise SystemExit(f"\nCannot reach Metabase at {self.base} ({e.reason}).\n"
                             "Start it with:  docker start metabase   then wait about a minute.")


def as_list(result):
    """Some Metabase versions return a list, others {'data': [...]}."""
    if isinstance(result, dict) and "data" in result:
        return result["data"]
    return result or []


def main():
    mb = Metabase(MB_URL)
    print(f"Metabase: {MB_URL}")

    props = mb.call("GET", "/api/session/properties")
    if not props.get("has-user-setup", True):
        raise SystemExit("Metabase's first-time setup isn't finished. Open "
                         f"{MB_URL}, create your admin account, then run this again.")

    email = os.environ.get("MB_EMAIL") or input("Metabase email: ").strip()
    password = os.environ.get("MB_PASSWORD") or getpass.getpass("Metabase password: ")
    mb.token = mb.call("POST", "/api/session", {"username": email, "password": password})["id"]
    print("Logged in to Metabase.")

    # 1. Database connection (reuse if it already exists)
    db = next((d for d in as_list(mb.call("GET", "/api/database"))
               if d.get("engine") == "postgres"
               and (d.get("details") or {}).get("dbname") == DB_NAME), None)
    if db:
        print(f"Database connection already exists (id {db['id']}).")
    else:
        pg_password = os.environ.get("PG_PASSWORD") or getpass.getpass("Postgres password (user postgres): ")
        details = {
            "host": os.environ.get("PG_HOST", "host.docker.internal"),
            "port": int(os.environ.get("PG_PORT", "5432")),
            "dbname": DB_NAME,
            "user": os.environ.get("PG_USER", "postgres"),
            "password": pg_password,
            "ssl": False,
        }
        db = mb.call("POST", "/api/database",
                     {"engine": "postgres", "name": DB_DISPLAY_NAME, "details": details})
        print(f"Connected Metabase to {DB_NAME} (id {db['id']}).")
    db_id = db["id"]

    mb.call("POST", f"/api/database/{db_id}/sync_schema", {}, ok_errors=(404,))
    print("Syncing tables...")
    time.sleep(int(os.environ.get("MB_SYNC_WAIT", "15")))
    tables = [t["name"] for t in as_list(mb.call("GET", f"/api/database/{db_id}/metadata")
                                         .get("tables", []))]
    print(f"Metabase sees {len(tables)} tables: {', '.join(sorted(tables))}")

    # 2. Collection to keep the group's work together
    coll = next((c for c in as_list(mb.call("GET", "/api/collection"))
                 if c.get("name") == COLLECTION_NAME and not c.get("archived")), None)
    if not coll:
        coll = (mb.call("POST", "/api/collection", {"name": COLLECTION_NAME}, ok_errors=(400,))
                or mb.call("POST", "/api/collection", {"name": COLLECTION_NAME, "color": "#509EE3"}))
    coll_id = coll["id"]

    existing = {i["name"]: i["id"] for i in
                as_list(mb.call("GET", f"/api/collection/{coll_id}/items?models=card"))}

    # 3. Saved SQL questions
    card_ids = []
    for q in QUESTIONS:
        if q["name"] in existing:
            card_id = existing[q["name"]]
            print(f"Question exists: {q['name']}")
        else:
            card_id = mb.call("POST", "/api/card", {
                "name": q["name"],
                "display": q["display"],
                "collection_id": coll_id,
                "visualization_settings": q["viz"],
                "dataset_query": {"type": "native", "database": db_id,
                                  "native": {"query": q["sql"]}},
            })["id"]
            print(f"Created question: {q['name']}")
        card_ids.append((card_id, q["size"]))

    # 4. Dashboard with all questions (non-fatal if this Metabase version differs)
    try:
        dash_list = as_list(mb.call("GET", f"/api/collection/{coll_id}/items?models=dashboard"))
        dash = next((d for d in dash_list if d["name"] == DASHBOARD_NAME), None)
        if dash:
            print(f"Dashboard exists: {DASHBOARD_NAME}")
        else:
            dash = mb.call("POST", "/api/dashboard", {"name": DASHBOARD_NAME, "collection_id": coll_id})
            dashcards, row, col = [], 0, 0
            for i, (card_id, (w, h)) in enumerate(card_ids):
                if col + w > 24:
                    row, col = row + h, 0
                dashcards.append({"id": -(i + 1), "card_id": card_id, "row": row, "col": col,
                                  "size_x": w, "size_y": h, "parameter_mappings": [],
                                  "visualization_settings": {}})
                col += w
            mb.call("PUT", f"/api/dashboard/{dash['id']}", {"dashcards": dashcards})
            print(f"Created dashboard: {DASHBOARD_NAME}")
        print(f"\nOpen the dashboard: {MB_URL}/dashboard/{dash['id']}")
    except SystemExit as e:
        print(f"\nQuestions were created, but the dashboard step failed on this Metabase version:\n{e}\n"
              "Add the questions to a dashboard by hand (New > Dashboard).")

    print(f"Open the collection: {MB_URL}/collection/{coll_id}")
    print("Done.")


if __name__ == "__main__":
    main()
