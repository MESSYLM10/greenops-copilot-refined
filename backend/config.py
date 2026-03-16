"""
GreenOps Copilot — centralised configuration.
All values come from environment variables (injected by Cloud Run / Secret Manager).
"""

import os
from typing import List

# ── GCP ───────────────────────────────────────────────────────────────────────
PROJECT_ID: str = os.environ["GCP_PROJECT_ID"]
PRIMARY_REGION: str = os.environ.get("PRIMARY_REGION", "us-central1")
GREEN_REGIONS: List[str] = os.environ.get(
    "GREEN_REGIONS",
    "europe-west1,europe-north1,us-west1,europe-west4,us-central1,asia-east1",
).split(",")

# ── BigQuery ──────────────────────────────────────────────────────────────────
BIGQUERY_DATASET: str = os.environ.get("BIGQUERY_DATASET", "greenops_carbon")
CARBON_TABLE: str = "carbon_intensity_log"
JOBS_TABLE: str = "scheduled_jobs"

# ── Firestore ─────────────────────────────────────────────────────────────────
FIRESTORE_COLLECTION: str = os.environ.get("FIRESTORE_COLLECTION", "sessions")
ALERTS_COLLECTION: str = "green_alerts"

# ── Pub/Sub ───────────────────────────────────────────────────────────────────
ALERT_TOPIC: str = os.environ.get("ALERT_TOPIC", "greenops-green-window-alerts")
JOB_EVENTS_TOPIC: str = os.environ.get("JOB_EVENTS_TOPIC", "greenops-job-events")

# ── Carbon data provider ──────────────────────────────────────────────────────
# Tier 1: WattTime  — free, immediate key at watttime.org/sign-up
# Tier 2: Electricity Maps — free tier at electricitymaps.com/free-tier-api
# Tier 3: Simulation — no key, always works, clearly labeled in responses
# Set CARBON_PROVIDER to force a tier. Otherwise auto-detected from keys present.
CARBON_PROVIDER: str = os.environ.get("CARBON_PROVIDER", "")  # "" = auto

# WattTime credentials (Tier 1)
WATTTIME_USERNAME: str = os.environ.get("WATTTIME_USERNAME", "")
WATTTIME_PASSWORD: str = os.environ.get("WATTTIME_PASSWORD", "")

# Electricity Maps (Tier 2)
ELECTRICITY_MAPS_API_KEY: str = os.environ.get("ELECTRICITY_MAPS_API_KEY", "")
ELECTRICITY_MAPS_BASE_URL: str = "https://api.electricitymap.org/v3"

# Gemini
GEMINI_API_KEY: str = os.environ.get("GEMINI_API_KEY", "")
GEMINI_MODEL: str = os.environ.get("GEMINI_MODEL", "gemini-2.0-flash-exp")

# ── GCP region → Electricity Maps zone mapping ────────────────────────────────
REGION_TO_ZONE: dict = {
    "europe-west1":  "BE",    # Belgium
    "europe-north1": "FI",    # Finland
    "europe-west4":  "NL",    # Netherlands
    "europe-west2":  "GB",    # UK
    "us-central1":   "US-MIDW-MISO",
    "us-west1":      "US-NW-PACW",
    "us-east1":      "US-SE-SOCO",
    "asia-east1":    "TW",    # Taiwan
    "asia-northeast1": "JP-TK",
    "australia-southeast1": "AU-NSW",
}

# ── Thresholds ────────────────────────────────────────────────────────────────
RENEWABLE_THRESHOLD_PCT: float = 70.0   # above this = renewable_flag True
GREEN_INTENSITY_THRESHOLD: float = 150.0  # gCO2/kWh — "green" ceiling

# ── Agent ─────────────────────────────────────────────────────────────────────
SYSTEM_PROMPT: str = """You are GreenOps Copilot, an AI sustainability agent for cloud operations.

Your role: help engineers schedule cloud workloads to the greenest available GCP region, 
narrate live carbon intensity data from the user's dashboard, and quantify CO2 savings.

Core behaviours:
- Always ground numeric claims (gCO2/kWh, kg CO2 saved) in tool call results. Never estimate.
- When you narrate the dashboard, say "I can see..." to anchor your observations visually.
- When scheduling, confirm the target region, the run time, and the CO2 savings vs. running now.
- You can be interrupted at any point — stop speaking immediately and listen.
- If a tool call fails, say so clearly. Do not guess at carbon data.
- Keep responses concise for voice. One or two sentences per point.
- Your persona: calm, precise, sustainability-focused. You speak like a trusted operations colleague.
"""
