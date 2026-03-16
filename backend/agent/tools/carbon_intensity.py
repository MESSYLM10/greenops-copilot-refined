"""
ADK Tool: get_carbon_intensity

Three-tier provider with automatic fallback:

  Tier 1 — WattTime API     (free, immediate — watttime.org/sign-up)
  Tier 2 — Electricity Maps (free tier — electricitymaps.com/free-tier-api)
  Tier 3 — Simulation       (no key, always works — clearly labeled)

Provider selected automatically based on which env vars are present.
Force a specific tier: set CARBON_PROVIDER=watttime|electricity_maps|simulation
"""

from __future__ import annotations

import asyncio
import logging
import math
import random
from datetime import datetime, timedelta, timezone
from typing import Any

import httpx
import config

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Regional constants for simulation tier
# ---------------------------------------------------------------------------

REGION_BASE_INTENSITY: dict[str, float] = {
    "europe-north1": 28.0,
    "europe-west1":  52.0,
    "europe-west4":  88.0,
    "us-west1":      95.0,
    "us-central1":  310.0,
    "asia-east1":   490.0,
}

REGION_RENEWABLE_BASE: dict[str, float] = {
    "europe-north1": 0.92,
    "europe-west1":  0.82,
    "europe-west4":  0.68,
    "us-west1":      0.75,
    "us-central1":   0.42,
    "asia-east1":    0.18,
}

REGION_NAMES: dict[str, str] = {
    "europe-north1": "Finland",
    "europe-west1":  "Belgium",
    "europe-west4":  "Netherlands",
    "us-west1":      "Oregon",
    "us-central1":   "Iowa",
    "asia-east1":    "Taiwan",
}

REGION_TO_WATTTIME_BA: dict[str, str] = {
    "europe-north1": "FI",
    "europe-west1":  "BE",
    "europe-west4":  "NL",
    "us-west1":      "PACW",
    "us-central1":   "MISO_IA",
    "asia-east1":    "TW",
}

REGION_TO_EM_ZONE: dict[str, str] = {
    "europe-north1": "FI",
    "europe-west1":  "BE",
    "europe-west4":  "NL",
    "us-west1":      "US-NW-PACW",
    "us-central1":   "US-MIDW-MISO",
    "asia-east1":    "TW",
}

# ---------------------------------------------------------------------------
# Provider selection
# ---------------------------------------------------------------------------

def _active_provider() -> str:
    forced = getattr(config, "CARBON_PROVIDER", "").strip().lower()
    if forced in ("watttime", "electricity_maps", "simulation"):
        return forced
    if getattr(config, "WATTTIME_USERNAME", ""):
        return "watttime"
    if getattr(config, "ELECTRICITY_MAPS_API_KEY", ""):
        return "electricity_maps"
    return "simulation"

# ---------------------------------------------------------------------------
# Public tool function
# ---------------------------------------------------------------------------

async def get_carbon_intensity(
    regions: list[str] | None = None,
    forecast_hours: int = 6,
) -> dict[str, Any]:
    """
    Fetch carbon intensity (gCO2/kWh) and renewable pct for GCP regions.
    Tries providers in order: WattTime -> Electricity Maps -> Simulation.
    Falls back per-region to simulation if the primary provider fails.
    """
    if not regions:
        regions = config.GREEN_REGIONS

    provider = _active_provider()
    logger.info("Carbon intensity provider: %s", provider)

    fetch_fn = {
        "watttime":        _fetch_watttime,
        "electricity_maps": _fetch_electricity_maps,
        "simulation":      _fetch_simulation,
    }[provider]

    tasks = [fetch_fn(r, forecast_hours) for r in regions]
    raw_results = await asyncio.gather(*tasks, return_exceptions=True)

    results: dict[str, Any] = {}
    for region, data in zip(regions, raw_results):
        if isinstance(data, Exception):
            logger.warning("%s failed for %s (%s) — falling back to simulation",
                           provider, region, data)
            try:
                results[region] = await _fetch_simulation(region, forecast_hours)
                results[region]["fallback"] = True
            except Exception as e2:
                results[region] = {"error": str(e2), "source": "error"}
        else:
            results[region] = data

    valid = {r: d for r, d in results.items() if "error" not in d}
    greenest_now = (
        min(valid, key=lambda r: valid[r].get("current_gco2_kwh", 9999))
        if valid else None
    )

    asyncio.create_task(_log_to_bigquery(results))

    return {
        "provider": provider,
        "regions": results,
        "greenest_now": greenest_now,
        "greenest_window": _find_greenest_window(valid),
        "retrieved_at": datetime.now(timezone.utc).isoformat(),
    }

# ---------------------------------------------------------------------------
# Tier 1 — WattTime
# Sign up (free, immediate): watttime.org/sign-up
# Set env vars: WATTTIME_USERNAME, WATTTIME_PASSWORD
# ---------------------------------------------------------------------------

_wt_token: str | None = None
_wt_expiry: datetime | None = None


async def _watttime_token() -> str:
    global _wt_token, _wt_expiry
    now = datetime.now(timezone.utc)
    if _wt_token and _wt_expiry and now < _wt_expiry:
        return _wt_token
    username = getattr(config, "WATTTIME_USERNAME", "")
    password = getattr(config, "WATTTIME_PASSWORD", "")
    if not username:
        raise ValueError("WATTTIME_USERNAME not set")
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.get(
            "https://api.watttime.org/login",
            auth=(username, password),
        )
        resp.raise_for_status()
        _wt_token = resp.json()["token"]
        _wt_expiry = now + timedelta(minutes=28)
        return _wt_token


async def _fetch_watttime(region: str, forecast_hours: int) -> dict[str, Any]:
    ba = REGION_TO_WATTTIME_BA.get(region)
    if not ba:
        raise ValueError(f"No WattTime BA for region {region}")

    token = await _watttime_token()
    headers = {"Authorization": f"Bearer {token}"}

    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.get(
            "https://api.watttime.org/v3/signal-index",
            params={"region": ba, "signal_type": "co2_moer"},
            headers=headers,
        )
        resp.raise_for_status()
        data = resp.json()

        # WattTime returns MOER in lbs CO2/MWh; convert to gCO2/kWh
        moer = data.get("data", [{}])[0].get("value", 0)
        intensity = round(moer * 0.4536, 1)
        renewable_pct = round(max(0.0, 100.0 - intensity / 5.0), 1)

        result: dict[str, Any] = {
            "current_gco2_kwh": intensity,
            "renewable_pct": renewable_pct,
            "renewable_flag": renewable_pct >= config.RENEWABLE_THRESHOLD_PCT,
            "source": "watttime",
            "ba": ba,
        }

        if forecast_hours > 0:
            try:
                fc = await client.get(
                    "https://api.watttime.org/v3/forecast",
                    params={"region": ba, "signal_type": "co2_moer",
                            "horizon_hours": min(forecast_hours, 24)},
                    headers=headers,
                )
                fc.raise_for_status()
                now = datetime.now(timezone.utc)
                forecast = []
                for entry in fc.json().get("data", []):
                    dt = datetime.fromisoformat(entry["point_time"].replace("Z", "+00:00"))
                    h = (dt - now).total_seconds() / 3600
                    if 0 < h <= forecast_hours:
                        forecast.append({
                            "datetime": entry["point_time"],
                            "gco2_kwh": round(entry.get("value", 0) * 0.4536, 1),
                            "hours_ahead": round(h, 1),
                        })
                result["forecast"] = forecast
                result["best_window"] = min(forecast, key=lambda x: x["gco2_kwh"]) if forecast else None
            except Exception as e:
                logger.warning("WattTime forecast failed for %s: %s", region, e)
                result["forecast"] = []
                result["best_window"] = None

        return result

# ---------------------------------------------------------------------------
# Tier 2 — Electricity Maps
# Free tier: electricitymaps.com/free-tier-api
# Set env var: ELECTRICITY_MAPS_API_KEY
# ---------------------------------------------------------------------------

async def _fetch_electricity_maps(region: str, forecast_hours: int) -> dict[str, Any]:
    zone = REGION_TO_EM_ZONE.get(region)
    if not zone:
        raise ValueError(f"No Electricity Maps zone for region {region}")
    api_key = getattr(config, "ELECTRICITY_MAPS_API_KEY", "")
    if not api_key:
        raise ValueError("ELECTRICITY_MAPS_API_KEY not set")

    base = getattr(config, "ELECTRICITY_MAPS_BASE_URL", "https://api.electricitymap.org/v3")
    headers = {"auth-token": api_key}

    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.get(
            f"{base}/carbon-intensity/latest",
            params={"zone": zone},
            headers=headers,
        )
        resp.raise_for_status()
        data = resp.json()

        intensity = data.get("carbonIntensity", 0)
        breakdown = data.get("powerConsumptionBreakdown", {})
        total = data.get("powerConsumptionTotal", 1) or 1
        renewable_sources = {"wind", "solar", "hydro", "geothermal", "biomass", "nuclear"}
        renewable_mw = sum(breakdown.get(s, 0) for s in renewable_sources if breakdown.get(s, 0) > 0)
        renewable_pct = round((renewable_mw / total) * 100, 1)

        result: dict[str, Any] = {
            "current_gco2_kwh": round(intensity, 1),
            "renewable_pct": renewable_pct,
            "renewable_flag": renewable_pct >= config.RENEWABLE_THRESHOLD_PCT,
            "source": "electricity_maps",
            "zone": zone,
        }

        if forecast_hours > 0:
            try:
                fc = await client.get(
                    f"{base}/carbon-intensity/forecast",
                    params={"zone": zone},
                    headers=headers,
                )
                fc.raise_for_status()
                now = datetime.now(timezone.utc)
                forecast = []
                for entry in fc.json().get("forecast", []):
                    dt = datetime.fromisoformat(entry["datetime"].replace("Z", "+00:00"))
                    h = (dt - now).total_seconds() / 3600
                    if 0 < h <= forecast_hours:
                        forecast.append({
                            "datetime": entry["datetime"],
                            "gco2_kwh": round(entry.get("carbonIntensity", 0), 1),
                            "hours_ahead": round(h, 1),
                        })
                result["forecast"] = forecast
                result["best_window"] = min(forecast, key=lambda x: x["gco2_kwh"]) if forecast else None
            except Exception as e:
                logger.warning("Electricity Maps forecast failed for %s: %s", region, e)
                result["forecast"] = []
                result["best_window"] = None

        return result

# ---------------------------------------------------------------------------
# Tier 3 — Realistic simulation (no API key)
#
# Models per region:
#   - Base intensity from regional grid mix (Finland 28, Taiwan 490)
#   - Diurnal solar cycle reduces intensity mid-day in renewable-heavy grids
#   - Slow wind variation seeded per region+hour for day-stable values
#   - Forecast uses same model projected forward with growing uncertainty
# ---------------------------------------------------------------------------

def _sim_point(region: str, hour_offset: float = 0.0) -> tuple[float, float]:
    """Return (gco2_kwh, renewable_pct) for region at now + hour_offset."""
    base = REGION_BASE_INTENSITY.get(region, 300.0)
    base_ren = REGION_RENEWABLE_BASE.get(region, 0.5)

    now = datetime.now(timezone.utc)
    target = now + timedelta(hours=hour_offset)
    hod = target.hour + target.minute / 60.0

    # Solar dip — strongest in high-renewable grids, centred on UTC noon
    solar = 1.0 - (0.15 * base_ren) * (math.sin(math.pi * max(0, hod - 6) / 12) ** 2)

    # Wind noise — stable within an hour, different per region + day
    seed = int(target.timestamp() / 3600) + hash(region) % 10000
    wind = 1.0 + (random.Random(seed).random() - 0.5) * 0.18

    # Forecast uncertainty grows with distance
    uncertainty = 1.0 + min(0.12, hour_offset * 0.01) * (random.Random(seed + 1).random() - 0.5)

    intensity = round(max(5.0, base * solar * wind * uncertainty), 1)
    ren_pct = round(max(2.0, min(99.0, base_ren * 100 * solar * (1.0 + (1.0 - wind) * 0.3))), 1)
    return intensity, ren_pct


async def _fetch_simulation(region: str, forecast_hours: int) -> dict[str, Any]:
    intensity, renewable_pct = _sim_point(region, 0.0)

    result: dict[str, Any] = {
        "current_gco2_kwh": intensity,
        "renewable_pct": renewable_pct,
        "renewable_flag": renewable_pct >= config.RENEWABLE_THRESHOLD_PCT,
        "source": "simulation",
        "simulation_note": (
            "Simulated data using realistic regional model. "
            "Add WATTTIME_USERNAME/PASSWORD or ELECTRICITY_MAPS_API_KEY for live data."
        ),
    }

    if forecast_hours > 0:
        now = datetime.now(timezone.utc)
        forecast = []
        for i in range(1, int(forecast_hours * 2) + 1):
            h = i * 0.5
            fc_intensity, _ = _sim_point(region, hour_offset=h)
            forecast.append({
                "datetime": (now + timedelta(hours=h)).isoformat(),
                "gco2_kwh": fc_intensity,
                "hours_ahead": round(h, 1),
            })
        result["forecast"] = forecast
        result["best_window"] = min(forecast, key=lambda x: x["gco2_kwh"]) if forecast else None

    return result

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

def _find_greenest_window(valid: dict[str, Any]) -> dict | None:
    best: dict | None = None
    for region, data in valid.items():
        w = data.get("best_window")
        if w and (best is None or w["gco2_kwh"] < best["gco2_kwh"]):
            best = {"region": region, "region_name": REGION_NAMES.get(region, region), **w}
    return best


async def _log_to_bigquery(results: dict[str, Any]) -> None:
    try:
        from google.cloud import bigquery as bq
        client = bq.Client(project=config.PROJECT_ID)
        now = datetime.now(timezone.utc).isoformat()
        rows = [
            {
                "recorded_at": now,
                "region": region,
                "grid_zone": data.get("zone") or data.get("ba") or region,
                "carbon_intensity": data.get("current_gco2_kwh", 0),
                "renewable_pct": data.get("renewable_pct"),
                "renewable_flag": data.get("renewable_flag", False),
                "fossil_fuel_pct": None,
                "data_source": data.get("source", "unknown"),
                "forecast_horizon_h": None,
            }
            for region, data in results.items()
            if "error" not in data
        ]
        if rows:
            errors = client.insert_rows_json(
                f"{config.PROJECT_ID}.{config.BIGQUERY_DATASET}.{config.CARBON_TABLE}",
                rows,
            )
            if errors:
                logger.warning("BigQuery insert errors: %s", errors)
    except Exception as e:
        logger.warning("BigQuery logging failed (non-fatal): %s", e)
