# phase3_dashboard_setup_v2.py
# DSAI-691 Group 6: U.S. Hospital Quality & Cost -- Phase 3 dashboard (v2)
#
# Changes from phase3_dashboard_setup.py:
#   - 2.3 and 2.4 combined into one line chart (2.3): readmission and death-rate
#     distributions on one axis, as % of hospitals. 2.4 is removed and
#     2.5-2.8 are renumbered 2.4-2.7.
#   - 6.2 changed from a spending row chart to a U.S. state map colored by average
#     CMS star rating, placed next to the 6.1 spending map.
#   - Edits made by hand in Metabase on the v1 dashboard, copied in here:
#       * new titles for K1-K3, 1.1, 1.2, 2.6, 3.1-3.4, 4.1, 4.2 (KPI names here,
#         query titles in dashboard_queries.sql)
#       * 3.1 and 3.2 shown as bar charts instead of scatter plots
#       * ordinal x-axis on 1.1, 1.2, 2.6, 3.3, 3.4
#       * tab intro cards show only the section question, centered
#
# Builds the Phase 3 Metabase dashboard from sql_queries_for_viz/dashboard_queries.sql:
#   - one saved question per query (24), using a range of chart types
#   - 3 headline number cards (KPIs)
#   - one dashboard with a tab per section:
#       1. Headline  2. Distributions  3. Clinical Outcomes
#       4. Patient Experience  5. Ownership  6. Geography
#
# The SQL, titles, and descriptions are read from dashboard_queries.sql, so edits to
# that file show up the next time this script runs. Chart types and settings live in
# CHARTS below. Each chart has an "extend" note with ideas for the next revision;
# it is shown in the card description (hover the card title in Metabase).
#
# Before running:
#   1. Metabase is running in Docker (docker start metabase)
#   2. You have a Metabase account at http://localhost:3000
#   3. create_and_load.sql has built the hospital_quality database
#
# Run from the repo folder:
#   python3 metabase/phase3_dashboard_setup_v2.py              # create what is missing
#   python3 metabase/phase3_dashboard_setup_v2.py --overwrite  # also replace existing
#   python3 metabase/phase3_dashboard_setup_v2.py --dry-run    # only print the plan
#
# By default, questions and the dashboard that already exist are left alone, so
# changes made by hand in Metabase are not lost. --overwrite replaces them with
# what is in this file.

import argparse
import getpass
import pathlib
import re
import time

import requests

METABASE_URL = "http://localhost:3000"
DB_NAME = "hospital_quality"
DB_DISPLAY_NAME = "Hospital Quality (Group 6)"
COLLECTION_NAME = "Group 6: Phase 3 Dashboard"
DASHBOARD_NAME = "Does spending buy better hospital care?"
SQL_FILE = pathlib.Path(__file__).resolve().parent.parent / "sql_queries_for_viz" / "dashboard_queries.sql"

# Colors used across charts so the same idea always has the same color
GREEN, RED, BLUE, ORANGE, PURPLE, GRAY = "#84BB4C", "#ED6E6E", "#509EE3", "#F9CF48", "#A989C5", "#949AAB"


# ---------------------------------------------------------------------------
# Tabs: name, the section's question (shown at the top of the tab), and ideas
# for the next revision of the whole tab.
# ---------------------------------------------------------------------------
TABS = {
    1: ("1. Headline",
        "Do higher-spending hospitals earn higher quality ratings?",
        "Add a dashboard filter for state or ownership; add a one-line takeaway under each chart."),
    2: ("2. Distributions",
        "How are spending and each outcome spread across hospitals?",
        "Mark the national median on each histogram."),
    3: ("3. Clinical Outcomes",
        "Does extra spending reduce readmissions, infections, or deaths?",
        "Add a trend line or correlation number next to each scatter; click-through from a dot to hospital detail."),
    4: ("4. Patient Experience",
        "Where does the star-rating gap come from?",
        "Show the actual survey topics side by side for Q1 vs Q4; filter 4.3 by ownership."),
    5: ("5. Ownership",
        "Who runs the hospitals, and what do they cost?",
        "Use the same for-profit / non-profit / government groups on every chart; add hospital counts as labels."),
    6: ("6. Geography",
        "Which states spend the most, and why?",
        "Link the maps to a state filter for the other tabs."),
}


# ---------------------------------------------------------------------------
# Extra headline numbers (not in dashboard_queries.sql). Simple KPIs that open
# the story. Delete or replace these freely.
# ---------------------------------------------------------------------------
KPIS = [
    {
        "key": "K1", "tab": 1, "width": 8, "height": 4,
        "name": "Hospitals w/ Medicare spending score",
        "description": "Number of hospitals with a Medicare spending per beneficiary (MSPB) ratio, the base for most charts.",
        "display": "scalar",
        "settings": {},
        "sql": """
SELECT COUNT(*) AS hospitals
FROM fact_spending
WHERE measure_id = 'MSPB-1'
  AND mspb_ratio IS NOT NULL
""",
        "extend": "Switch to a 'Trend' number if a second year of CMS data is loaded.",
    },
    {
        "key": "K2", "tab": 1, "width": 8, "height": 4,
        "name": "Spending vs. CMS Star Rating",
        "description": "Pearson correlation between each hospital's spending ratio and its CMS overall star rating. "
                       "0 = no relationship; below 0 = higher spenders tend to have lower ratings.",
        "display": "scalar",
        "settings": {"column_settings": {'["name","correlation"]': {"decimals": 3}}},
        "sql": """
SELECT ROUND(CORR(s.mspb_ratio, h.overall_rating)::NUMERIC, 3) AS correlation
FROM dim_hospital h
JOIN fact_spending s
     ON s.facility_id = h.facility_id AND s.measure_id = 'MSPB-1'
WHERE s.mspb_ratio IS NOT NULL
  AND h.overall_rating IS NOT NULL
""",
        "extend": "Add matching correlation cards for readmissions and mortality.",
    },
    {
        "key": "K3", "tab": 1, "width": 8, "height": 4,
        "name": "Share of Rated Hospitals, 4 and 5 Star",
        "description": "Percent of hospitals with a CMS overall rating that earn 4 or 5 stars. Compare with 1.2 by spending tier.",
        "display": "gauge",
        "settings": {
            "gauge.segments": [
                {"min": 0, "max": 25, "color": RED, "label": ""},
                {"min": 25, "max": 50, "color": ORANGE, "label": ""},
                {"min": 50, "max": 100, "color": GREEN, "label": ""},
            ],
            "column_settings": {'["name","pct_4_or_5_star"]': {"suffix": "%"}},
        },
        "sql": """
SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE overall_rating >= 4) / COUNT(*), 1) AS pct_4_or_5_star
FROM dim_hospital
WHERE overall_rating IS NOT NULL
""",
        "extend": "Pick segment cut-offs that match the story (for example the national share).",
    },
]


# ---------------------------------------------------------------------------
# One entry per query in dashboard_queries.sql, keyed by its number (1.1, 1.2...).
#   display  : Metabase chart type
#   settings : Metabase visualization settings
#   width/height : size on the dashboard (the grid is 24 units wide)
#   extend   : ideas for the next revision
# ---------------------------------------------------------------------------
def pct(col):
    """Show a column with a % suffix."""
    return {f'["name","{col}"]': {"suffix": "%"}}


CHARTS = {
    # ----- Section 1: Headline -------------------------------------------------
    "1.1": {
        "display": "combo", "width": 14, "height": 8,
        "settings": {
            "graph.x_axis.scale": "ordinal",
            "graph.dimensions": ["spending_quartile"],
            "graph.metrics": ["avg_star_rating", "avg_hf_readmission_pct"],
            "series_settings": {
                "avg_star_rating": {"display": "bar", "axis": "left", "color": BLUE,
                                    "title": "Avg CMS star rating"},
                "avg_hf_readmission_pct": {"display": "line", "axis": "right", "color": RED,
                                           "title": "Avg HF readmission %"},
            },
            "graph.show_values": True,
            "graph.x_axis.title_text": "Spending quartile",
        },
        "extend": "Add avg_hf_death_pct and avg_psi_90 as more lines, or make one small chart per outcome.",
    },
    "1.2": {
        "display": "bar", "width": 10, "height": 8,
        "settings": {
            "graph.x_axis.scale": "ordinal",
            "graph.dimensions": ["spending_level"],
            "graph.metrics": ["pct_top_rated"],
            "series_settings": {"pct_top_rated": {"color": GREEN, "title": "% rated 4-5 stars"}},
            "graph.show_values": True,
            "graph.x_axis.title_text": "Spending tier",
            "graph.y_axis.title_text": "% of hospitals rated 4-5 stars",
            "column_settings": pct("pct_top_rated"),
        },
        "extend": "Add a goal line at the national share (card K3) to show which tiers fall below it.",
    },

    # ----- Section 2: Distributions ---------------------------------------------
    "2.1": {
        "display": "bar", "width": 12, "height": 7,
        "settings": {
            "graph.dimensions": ["spending_bucket"],
            "graph.metrics": ["hospitals"],
            "graph.x_axis.scale": "ordinal",
            "series_settings": {"hospitals": {"color": BLUE}},
            "graph.x_axis.title_text": "Spending ratio band (1.0 = national median)",
            "graph.y_axis.title_text": "Hospitals",
        },
        "extend": "Color the bars below / above 1.0 differently to show cheaper vs. more expensive hospitals.",
    },
    "2.2": {
        "display": "bar", "width": 12, "height": 7,
        "settings": {
            "graph.dimensions": ["stars", "rating_type"],
            "graph.metrics": ["pct_of_hospitals"],
            "graph.x_axis.scale": "ordinal",
            "graph.x_axis.title_text": "Stars",
            "graph.y_axis.title_text": "% of hospitals",
            "column_settings": pct("pct_of_hospitals"),
        },
        "extend": "Add data labels; explain in a text card why the two ratings cover different hospitals.",
    },
    "2.3": {
        "display": "line", "width": 16, "height": 7,
        "settings": {
            "graph.dimensions": ["rate_pct_bucket", "outcome"],
            "graph.metrics": ["pct_of_hospitals"],
            "graph.x_axis.scale": "linear",
            "line.interpolate": "cardinal",
            "line.marker_enabled": True,
            "series_settings": {
                "HF readmission": {"color": RED},
                "HF death": {"color": PURPLE},
            },
            "graph.x_axis.title_text": "30-day heart-failure rate (%, lower = better)",
            "graph.y_axis.title_text": "% of hospitals",
            "column_settings": pct("pct_of_hospitals"),
        },
        "extend": "Overlay the readmission curve for the lowest and highest spending quartiles.",
    },
    "2.4": {
        "display": "pie", "width": 8, "height": 7,
        "settings": {
            "pie.dimension": "sir_bucket",
            "pie.metric": "hospital_results",
            "pie.show_legend": True,
            "pie.show_total": True,
            "pie.percent_visibility": "inside",
        },
        "extend": "Use a green-to-red color per bucket so 'below 1.0 = better than expected' stands out.",
    },
    "2.5": {
        "display": "table", "width": 24, "height": 6,
        "settings": {
            "table.column_formatting": [{
                "columns": ["cv_pct"], "type": "range",
                "colors": ["#FFFFFF", BLUE],
                "min_type": None, "max_type": None,
                "operator": "=", "value": "", "color": BLUE, "highlight_row": False,
            }],
            "column_settings": pct("cv_pct"),
        },
        "extend": "Add a bar chart of cv_pct next to the table; hide columns the audience does not need.",
    },
    "2.6": {
        "display": "line", "width": 12, "height": 7,
        "settings": {
            "graph.x_axis.scale": "ordinal",
            "graph.dimensions": ["spending_quartile"],
            "graph.metrics": ["p10_pct", "median_pct", "p90_pct"],
            "series_settings": {
                "p10_pct": {"color": GRAY, "line.style": "dashed", "title": "10th percentile"},
                "median_pct": {"color": RED, "title": "Median"},
                "p90_pct": {"color": GRAY, "line.style": "dashed", "title": "90th percentile"},
            },
            "line.marker_enabled": True,
            "graph.x_axis.title_text": "Spending quartile",
            "graph.y_axis.title_text": "HF readmission rate (%)",
        },
        "extend": "Add min and max as faint lines to show the full spread.",
    },
    "2.7": {
        "display": "scatter", "width": 12, "height": 7,
        "settings": {
            "graph.dimensions": ["sd_mspb"],
            "graph.metrics": ["sd_star_rating"],
            "scatter.bubble": "hospitals",
            "series_settings": {"sd_star_rating": {"color": ORANGE}},
            "graph.x_axis.title_text": "Spread of spending within the state (std dev)",
            "graph.y_axis.title_text": "Spread of star ratings (std dev)",
        },
        "extend": "Add a table version sorted by sd_mspb so specific states can be named.",
    },

    # ----- Section 3: Clinical Outcomes ------------------------------------------
    "3.1": {
        "display": "bar", "width": 12, "height": 8,
        "description": "One point per hospital with 150+ heart-failure cases: Medicare spending ratio "
                       "vs. 30-day heart-failure readmission rate. spend_percentile shows where each "
                       "hospital ranks on spending.",
        "settings": {
            "graph.x_axis.scale": "linear",
            "graph.dimensions": ["mspb_ratio"],
            "graph.metrics": ["hf_readmission_pct"],
            "series_settings": {"hf_readmission_pct": {"color": RED}},
            "graph.x_axis.title_text": "Spending ratio (1.0 = national median)",
            "graph.y_axis.title_text": "HF readmission rate (%)",
        },
        "extend": "Color the dots by star_rating (breakout) to show quality and cost at once.",
    },
    "3.2": {
        "display": "bar", "width": 12, "height": 8,
        "settings": {
            "graph.x_axis.scale": "linear",
            "graph.dimensions": ["spending_ratio"],
            "graph.metrics": ["mortality_rate"],
            "series_settings": {"mortality_rate": {"color": PURPLE}},
            "graph.x_axis.title_text": "Spending ratio (1.0 = national median)",
            "graph.y_axis.title_text": "HF death rate (%)",
        },
        "extend": "Limit to hospitals with enough cases (like 3.1) so small hospitals do not add noise.",
    },
    "3.3": {
        "display": "line", "width": 14, "height": 8,
        "settings": {
            "graph.x_axis.scale": "ordinal",
            "graph.dimensions": ["spending_quartile", "infection_type"],
            "graph.metrics": ["avg_infection_ratio"],
            "line.marker_enabled": True,
            "graph.show_goal": True,
            "graph.goal_value": 1.0,
            "graph.goal_label": "Expected (SIR = 1.0)",
            "graph.x_axis.title_text": "Spending quartile",
            "graph.y_axis.title_text": "Avg infection ratio (SIR, lower = better)",
        },
        "extend": "Shorten the infection names in SQL so the legend is easier to read.",
    },
    "3.4": {
        "display": "bar", "width": 10, "height": 8,
        "settings": {
            "graph.x_axis.scale": "ordinal",
            "graph.dimensions": ["spending_level"],
            "graph.metrics": ["avg_infection_sir"],
            "series_settings": {"avg_infection_sir": {"color": ORANGE, "title": "Avg infection ratio"}},
            "graph.show_values": True,
            "graph.show_goal": True,
            "graph.goal_value": 1.0,
            "graph.goal_label": "Expected (SIR = 1.0)",
            "graph.x_axis.title_text": "Spending tier",
            "graph.y_axis.title_text": "Avg SIR (lower = better)",
        },
        "extend": "Show the number of hospitals per tier as a label or tooltip.",
    },
    "3.5": {
        "display": "bar", "width": 24, "height": 7,
        "settings": {
            "graph.dimensions": ["spending_level"],
            "graph.metrics": ["pct_better", "pct_worse"],
            "series_settings": {
                "pct_better": {"color": GREEN, "title": "% better than national"},
                "pct_worse": {"color": RED, "title": "% worse than national"},
            },
            "graph.show_values": True,
            "graph.x_axis.title_text": "Spending tier",
            "graph.y_axis.title_text": "% of death and complication results",
            "column_settings": {**pct("pct_better"), **pct("pct_worse")},
        },
        "extend": "Split by measure (deaths vs. complications) to see which one drives the pattern.",
    },

    # ----- Section 4: Patient Experience -----------------------------------------
    "4.1": {
        "display": "line", "width": 10, "height": 8,
        "settings": {
            "graph.dimensions": ["patient_star_rating"],
            "graph.metrics": ["avg_spending_ratio"],
            "graph.x_axis.scale": "ordinal",
            "line.marker_enabled": True,
            "graph.show_values": True,
            "series_settings": {"avg_spending_ratio": {"color": BLUE, "title": "Avg spending ratio"}},
            "graph.show_goal": True,
            "graph.goal_value": 1.0,
            "graph.goal_label": "National median",
            "graph.x_axis.title_text": "Patient-survey star rating",
            "graph.y_axis.title_text": "Avg spending ratio",
        },
        "extend": "Add n_hospitals as bars on a second axis (combo) to show how many hospitals are behind each point.",
    },
    "4.2": {
        "display": "row", "width": 14, "height": 8,
        "settings": {
            "graph.dimensions": ["survey_topic"],
            "graph.metrics": ["star_gap"],
            "series_settings": {"star_gap": {"color": RED, "title": "Star gap (highest - lowest spend)"}},
            "graph.show_values": True,
            "graph.x_axis.title_text": "Survey topic",
            "graph.y_axis.title_text": "Star gap (negative = high spenders rate lower)",
        },
        "extend": "Make a second version with lowest_spend_stars and highest_spend_stars side by side.",
    },
    "4.3": {
        "display": "scatter", "width": 24, "height": 9,
        "settings": {
            "graph.dimensions": ["mspb_ratio", "patient_survey_stars"],
            "graph.metrics": ["pct_definitely_recommend"],
            "graph.x_axis.title_text": "Spending ratio (1.0 = national median)",
            "graph.y_axis.title_text": "% who would definitely recommend",
        },
        "extend": "Use a red-to-green color per star level; add a filter for hospital_ownership.",
    },

    # ----- Section 5: Ownership ---------------------------------------------------
    "5.1": {
        "display": "combo", "width": 12, "height": 8,
        "settings": {
            "graph.dimensions": ["hospital_ownership"],
            "graph.metrics": ["avg_star_rating", "avg_spending_ratio"],
            "series_settings": {
                "avg_star_rating": {"display": "bar", "axis": "left", "color": BLUE,
                                    "title": "Avg CMS star rating"},
                "avg_spending_ratio": {"display": "line", "axis": "right", "color": ORANGE,
                                       "title": "Avg spending ratio"},
            },
            "graph.x_axis.title_text": "Ownership",
        },
        "extend": "Shorten the ownership names (CASE in SQL) so the x-axis labels fit.",
    },
    "5.2": {
        "display": "bar", "width": 12, "height": 8,
        "settings": {
            "graph.dimensions": ["hospital_ownership", "value_group"],
            "graph.metrics": ["hospitals"],
            "stackable.stack_type": "normalized",
            "series_settings": {
                "1. High quality, low cost": {"color": GREEN},
                "2. High quality, high cost": {"color": BLUE},
                "3. Lower quality, low cost": {"color": ORANGE},
                "4. Lower quality, high cost": {"color": RED},
            },
            "graph.x_axis.title_text": "Ownership",
            "graph.y_axis.title_text": "Share of hospitals",
        },
        "extend": "Turn it into a row chart if the ownership names stay long.",
    },
    "5.3": {
        "display": "bar", "width": 24, "height": 8,
        "settings": {
            "graph.dimensions": ["census_region", "ownership_group"],
            "graph.metrics": ["pct_4_or_5_star"],
            "series_settings": {
                "For-profit": {"color": RED},
                "Non-profit": {"color": GREEN},
                "Government": {"color": BLUE},
            },
            "graph.show_values": True,
            "graph.x_axis.title_text": "Census region",
            "graph.y_axis.title_text": "% rated 4-5 stars",
            "column_settings": pct("pct_4_or_5_star"),
        },
        "extend": "Add a matching chart of avg_mspb by region and ownership.",
    },

    # ----- Section 6: Geography ---------------------------------------------------
    "6.1": {
        "display": "map", "width": 12, "height": 10,
        "settings": {
            "map.type": "region",
            "map.region": "us_states",
            "map.dimension": "state",
            "map.metric": "avg_mspb",
        },
        "extend": "Use matching color scales on 6.1 and 6.2 so the two maps are easy to compare.",
    },
    "6.2": {
        "display": "map", "width": 12, "height": 10,
        "settings": {
            "map.type": "region",
            "map.region": "us_states",
            "map.dimension": "state",
            "map.metric": "avg_star_rating",
        },
        "extend": "Compare with 6.1: states that are dark on both maps spend more and rate higher.",
    },
    "6.3": {
        "display": "scatter", "width": 12, "height": 8,
        "settings": {
            "graph.dimensions": ["avg_spending_ratio"],
            "graph.metrics": ["avg_hf_mortality"],
            "scatter.bubble": "n_hospitals",
            "series_settings": {"avg_hf_mortality": {"color": PURPLE}},
            "graph.x_axis.title_text": "State avg spending ratio",
            "graph.y_axis.title_text": "State avg HF death rate (%)",
        },
        "extend": "Add HAVING COUNT(*) >= 10 like the other state queries to drop tiny territories.",
    },
    "6.4": {
        "display": "scatter", "width": 12, "height": 8,
        "settings": {
            "graph.dimensions": ["pct_for_profit"],
            "graph.metrics": ["avg_mspb"],
            "scatter.bubble": "hospitals",
            "series_settings": {"avg_mspb": {"color": ORANGE}},
            "graph.x_axis.title_text": "% of hospitals that are for-profit",
            "graph.y_axis.title_text": "State avg spending ratio",
        },
        "extend": "Color the bubbles by census region to connect with 5.3.",
    },
}


# ---------------------------------------------------------------------------
# Read the queries from dashboard_queries.sql
# ---------------------------------------------------------------------------
QUERY_BLOCK = re.compile(
    r"^-- (?P<key>\d\.\d)\s+(?P<title>.*?)\n"         # -- 1.1  How do star ratings ...
    r"-- Description:\s*(?P<desc>.*?)\n"               # -- Description:  ...
    r"-- Metabase:.*?\n"                               # -- Metabase:     ... (ignored here)
    r"-- -{10,}\n"                                     # -- ---------------
    r"(?P<sql>.*?);",                                  # SQL up to the semicolon
    re.MULTILINE | re.DOTALL,
)


def clean_comment(text):
    """Join a multi-line '--' comment into one line of text."""
    lines = [line.lstrip("-").strip() for line in text.splitlines()]
    return " ".join(line for line in lines if line)


def read_queries():
    text = SQL_FILE.read_text()
    queries = {}
    for m in QUERY_BLOCK.finditer(text):
        queries[m["key"]] = {
            "title": clean_comment(m["title"]),
            "description": clean_comment(m["desc"]),
            "sql": m["sql"].strip(),
        }
    return queries


def build_questions():
    """Combine the SQL file with CHARTS and KPIS into one list of questions."""
    queries = read_queries()
    missing = sorted(set(CHARTS) - set(queries))
    if missing:
        print(f"Warning: no query found in {SQL_FILE.name} for {', '.join(missing)}. Skipping them.")
    extra = sorted(set(queries) - set(CHARTS))
    if extra:
        print(f"Note: {', '.join(extra)} are in the SQL file but have no chart yet. They are shown as tables.")

    questions = list(KPIS)
    for key, q in sorted(queries.items(), key=lambda kv: [int(p) for p in kv[0].split(".")]):
        chart = CHARTS.get(key, {"display": "table", "width": 12, "height": 7, "settings": {},
                                 "extend": "Pick a chart type."})
        questions.append({
            "key": key,
            "tab": int(key.split(".")[0]),
            "name": f"{key}  {q['title']}",
            "description": chart.get("description", q["description"]),
            "display": chart["display"],
            "settings": chart["settings"],
            "width": chart["width"],
            "height": chart["height"],
            "sql": q["sql"],
            "extend": chart["extend"],
        })
    return questions


# ---------------------------------------------------------------------------
# Metabase API helpers (same pattern as metabase_setup.py)
# ---------------------------------------------------------------------------
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
            print(f"Using database connection '{db['name']}' (id {db['id']}).")
            return db["id"]

    pg_user = input("Postgres user [postgres]: ").strip() or "postgres"
    pg_password = getpass.getpass(f"Postgres password (user {pg_user}): ")
    details = {
        "host": "host.docker.internal",   # from inside Docker, this means our laptop
        "port": 5432,
        "dbname": DB_NAME,
        "user": pg_user,
        "password": pg_password,
        "ssl": False,
    }
    db = api("POST", "/api/database",
             {"engine": "postgres", "name": DB_DISPLAY_NAME, "details": details})
    print(f"Connected Metabase to {DB_NAME} (id {db['id']}). Syncing tables...")
    api("POST", f"/api/database/{db['id']}/sync_schema")
    time.sleep(15)
    return db["id"]


def get_or_create_collection():
    for c in as_list(api("GET", "/api/collection")):
        if c.get("name") == COLLECTION_NAME and not c.get("archived"):
            return c["id"]
    return api("POST", "/api/collection", {"name": COLLECTION_NAME, "color": BLUE})["id"]


def card_description(q):
    return f"{q['description']}\n\nIdeas to extend: {q['extend']}"


def check_query(db_id, q):
    """Run the query once so SQL errors show up here instead of on the dashboard."""
    result = api("POST", "/api/dataset", {"database": db_id, "type": "native",
                                          "native": {"query": q["sql"]}})
    if result.get("status") != "completed":
        print(f"  ! {q['key']} SQL error: {str(result.get('error'))[:200]}")
        return False
    return True


def save_questions(db_id, collection_id, questions, overwrite):
    items = as_list(api("GET", f"/api/collection/{collection_id}/items?models=card"))
    existing = {item["name"]: item["id"] for item in items}

    failed = []
    for q in questions:
        if not check_query(db_id, q):
            failed.append(q["key"])
        card = {
            "name": q["name"],
            "description": card_description(q),
            "display": q["display"],
            "visualization_settings": q["settings"],
            "collection_id": collection_id,
            "dataset_query": {"type": "native", "database": db_id,
                              "native": {"query": q["sql"]}},
        }
        if q["name"] in existing:
            q["card_id"] = existing[q["name"]]
            if overwrite:
                api("PUT", f"/api/card/{q['card_id']}", card)
                print(f"Updated  {q['name']}  [{q['display']}]")
            else:
                print(f"Kept     {q['name']}  (already exists)")
        else:
            q["card_id"] = api("POST", "/api/card", card)["id"]
            print(f"Created  {q['name']}  [{q['display']}]")
    return failed


def layout(questions):
    """Place cards left to right on each tab, starting a new row when one is full.
    Each tab starts with a centered text card showing the section question."""
    dashcards, tabs = [], []
    next_id = -1
    for tab_num, (tab_name, question, ideas) in TABS.items():
        tab_id = -tab_num
        tabs.append({"id": tab_id, "name": tab_name})

        intro = f"## {question}\n"   # ideas stay in TABS for reference but are not shown
        dashcards.append({
            "id": next_id, "card_id": None, "dashboard_tab_id": tab_id,
            "row": 0, "col": 0, "size_x": 24, "size_y": 3,
            "parameter_mappings": [],
            "visualization_settings": {
                "virtual_card": {"name": None, "display": "text", "visualization_settings": {},
                                 "dataset_query": {}, "archived": False},
                "text": intro,
                "text.align_horizontal": "center",
                "text.align_vertical": "middle",
            },
        })
        next_id -= 1

        row, col, row_height = 3, 0, 0
        for q in (q for q in questions if q["tab"] == tab_num):
            if col + q["width"] > 24:
                row, col, row_height = row + row_height, 0, 0
            dashcards.append({
                "id": next_id, "card_id": q["card_id"], "dashboard_tab_id": tab_id,
                "row": row, "col": col, "size_x": q["width"], "size_y": q["height"],
                "parameter_mappings": [], "visualization_settings": {},
            })
            next_id -= 1
            col += q["width"]
            row_height = max(row_height, q["height"])
    return tabs, dashcards


def create_dashboard(collection_id, questions, overwrite):
    items = as_list(api("GET", f"/api/collection/{collection_id}/items?models=dashboard"))
    dashboard_id = next((i["id"] for i in items if i["name"] == DASHBOARD_NAME), None)

    if dashboard_id and not overwrite:
        print(f"Kept dashboard '{DASHBOARD_NAME}' (already exists; use --overwrite to rebuild it).")
        return dashboard_id
    if dashboard_id is None:
        dashboard_id = api("POST", "/api/dashboard", {
            "name": DASHBOARD_NAME, "collection_id": collection_id,
            "description": "DSAI-691 Group 6, Phase 3. Story: does spending more actually "
                           "result in better healthcare? One tab per section.",
        })["id"]

    tabs, dashcards = layout(questions)
    api("PUT", f"/api/dashboard/{dashboard_id}", {"tabs": tabs, "dashcards": dashcards})
    print(f"{'Rebuilt' if overwrite else 'Created'} dashboard '{DASHBOARD_NAME}' "
          f"with {len(tabs)} tabs and {len(questions)} charts.")
    return dashboard_id


def print_plan(questions):
    for tab_num, (tab_name, _, _) in TABS.items():
        print(f"\n{tab_name}")
        for q in (q for q in questions if q["tab"] == tab_num):
            title = q["name"].removeprefix(q["key"]).strip()
            print(f"  {q['key']:<4} {q['display']:<8} {q['width']:>2}x{q['height']:<2}  {title[:70]}")
    types = sorted({q["display"] for q in questions})
    print(f"\n{len(questions)} charts, {len(types)} chart types: {', '.join(types)}")


def main():
    parser = argparse.ArgumentParser(description="Build the Phase 3 Metabase dashboard.")
    parser.add_argument("--overwrite", action="store_true",
                        help="replace existing questions and the dashboard with this file's version")
    parser.add_argument("--dry-run", action="store_true",
                        help="print the charts and layout without contacting Metabase")
    args = parser.parse_args()

    questions = build_questions()
    if args.dry_run:
        print_plan(questions)
        return

    try:
        requests.get(METABASE_URL + "/api/health", timeout=10)
    except requests.exceptions.ConnectionError:
        print(f"Cannot reach Metabase at {METABASE_URL}.")
        print("Start it with: docker start metabase (then wait about a minute)")
        raise SystemExit(1)

    log_in()
    db_id = get_or_add_database()
    collection_id = get_or_create_collection()
    failed = save_questions(db_id, collection_id, questions, args.overwrite)
    dashboard_id = create_dashboard(collection_id, questions, args.overwrite)

    print(f"\nDashboard:  {METABASE_URL}/dashboard/{dashboard_id}")
    print(f"Collection: {METABASE_URL}/collection/{collection_id}")
    if failed:
        print(f"\nThese queries returned an SQL error and will show an error on the dashboard: "
              f"{', '.join(failed)}. Fix them in {SQL_FILE.name} and run with --overwrite.")
    print("Done.")


if __name__ == "__main__":
    main()
