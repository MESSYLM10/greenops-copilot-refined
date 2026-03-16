"""
ADK Tools: carbon_history, set_green_alert, get_dashboard_insight
"""

from __future__ import annotations

import logging
import uuid
from datetime import datetime, timezone
from typing import Any

from google.cloud import bigquery, firestore, pubsub_v1

import config

logger = logging.getLogger(__name__)

_bq_client: bigquery.Client | None = None
_fs_client: firestore.AsyncClient | None = None
_pubsub_publisher: pubsub_v1.PublisherClient | None = None


def _bq() -> bigquery.Client:
    global _bq_client
    if _bq_client is None:
        _bq_client = bigquery.Client(project=config.PROJECT_ID)
    return _bq_client


def _fs() -> firestore.AsyncClient:
    global _fs_client
    if _fs_client is None:
        _fs_client = firestore.AsyncClient(project=config.PROJECT_ID)
    return _fs_client


def _pubsub() -> pubsub_v1.PublisherClient:
    global _pubsub_publisher
    if _pubsub_publisher is None:
        _pubsub_publisher = pubsub_v1.PublisherClient()
    return _pubsub_publisher


###############################################################################
# query_carbon_history
###############################################################################

async def query_carbon_history(
    days: int = 7,
    region: str | None = None,
) -> dict[str, Any]:
    """
    Query BigQuery for historical carbon intensity and job savings.

    Args:
        days: Number of past days to include (1–90).
        region: Optional GCP region to filter by.

    Returns:
        {
          "period_days": 7,
          "total_co2_saved_kg": 84.3,
          "jobs_scheduled": 12,
          "avg_reduction_pct": 78.4,
          "greenest_region": "europe-north1",
          "carbon_trend": [...],   # daily avg gCO2/kWh per region
          "top_savings_job": {...}
        }
    """
    days = max(1, min(days, 90))
    region_filter = f"AND region = '{region}'" if region else ""

    jobs_query = f"""
        SELECT
            COUNT(*) AS jobs_count,
            ROUND(SUM(co2_saved_kg), 2) AS total_co2_saved_kg,
            ROUND(AVG(co2_reduction_pct), 1) AS avg_reduction_pct,
            target_region AS greenest_region
        FROM `{config.PROJECT_ID}.{config.BIGQUERY_DATASET}.{config.JOBS_TABLE}`
        WHERE scheduled_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL {days} DAY)
          AND status IN ('SCHEDULED', 'COMPLETE')
        GROUP BY target_region
        ORDER BY total_co2_saved_kg DESC
        LIMIT 1
    """

    trend_query = f"""
        SELECT
            DATE(recorded_at) AS date,
            region,
            ROUND(AVG(carbon_intensity), 1) AS avg_gco2_kwh,
            ROUND(AVG(renewable_pct), 1) AS avg_renewable_pct
        FROM `{config.PROJECT_ID}.{config.BIGQUERY_DATASET}.{config.CARBON_TABLE}`
        WHERE recorded_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL {days} DAY)
          {region_filter}
          AND forecast_horizon_h IS NULL
        GROUP BY date, region
        ORDER BY date DESC, avg_gco2_kwh ASC
        LIMIT 50
    """

    total_savings_query = f"""
        SELECT
            COUNT(*) AS total_jobs,
            ROUND(SUM(co2_saved_kg), 2) AS total_co2_saved_kg,
            ROUND(AVG(co2_reduction_pct), 1) AS avg_reduction_pct
        FROM `{config.PROJECT_ID}.{config.BIGQUERY_DATASET}.{config.JOBS_TABLE}`
        WHERE scheduled_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL {days} DAY)
    """

    try:
        client = _bq()

        jobs_rows = list(client.query(jobs_query).result())
        trend_rows = list(client.query(trend_query).result())
        totals_rows = list(client.query(total_savings_query).result())

        totals = dict(totals_rows[0]) if totals_rows else {}
        top_region = dict(jobs_rows[0]) if jobs_rows else {}

        trend = [
            {
                "date": str(row.date),
                "region": row.region,
                "avg_gco2_kwh": row.avg_gco2_kwh,
                "avg_renewable_pct": row.avg_renewable_pct,
            }
            for row in trend_rows
        ]

        return {
            "period_days": days,
            "total_co2_saved_kg": totals.get("total_co2_saved_kg", 0),
            "jobs_scheduled": totals.get("total_jobs", 0),
            "avg_reduction_pct": totals.get("avg_reduction_pct", 0),
            "greenest_region": top_region.get("greenest_region", "unknown"),
            "carbon_trend": trend,
            "summary": (
                f"Over the past {days} days, GreenOps saved "
                f"{totals.get('total_co2_saved_kg', 0):.1f} kg of CO₂ "
                f"across {totals.get('total_jobs', 0)} scheduled jobs, "
                f"with an average reduction of {totals.get('avg_reduction_pct', 0):.0f}%."
            ),
        }

    except Exception as e:
        logger.error("BigQuery history query failed: %s", e)
        return {"error": str(e), "period_days": days}


###############################################################################
# set_green_alert
###############################################################################

async def set_green_alert(
    region: str,
    threshold_gco2_kwh: float,
    session_id: str,
) -> dict[str, Any]:
    """
    Create a persistent green window alert. When the specified region drops below
    the carbon threshold, Pub/Sub fires and the agent speaks a proactive alert.

    Args:
        region: GCP region to monitor (e.g. "europe-west1").
        threshold_gco2_kwh: Carbon intensity threshold in gCO2/kWh.
        session_id: Firestore session ID to route the alert back to.

    Returns:
        { "alert_id": "alert-abc123", "region": ..., "threshold": ..., "status": "active" }
    """
    alert_id = f"alert-{uuid.uuid4().hex[:8]}"

    try:
        fs = _fs()
        await fs.collection(config.ALERTS_COLLECTION).document(alert_id).set({
            "alert_id": alert_id,
            "region": region,
            "threshold_gco2": threshold_gco2_kwh,
            "session_id": session_id,
            "created_at": datetime.now(timezone.utc).isoformat(),
            "active": True,
            "last_fired_at": None,
        })

        return {
            "alert_id": alert_id,
            "region": region,
            "threshold_gco2_kwh": threshold_gco2_kwh,
            "status": "active",
            "confirmation": (
                f"Alert set. I'll notify you when {region} drops below "
                f"{threshold_gco2_kwh:.0f} gCO₂/kWh."
            ),
        }

    except Exception as e:
        logger.error("Alert creation failed: %s", e)
        return {"error": str(e), "alert_id": alert_id}


async def fire_alert_if_threshold_met(
    region: str,
    current_gco2_kwh: float,
    session_callback,
) -> None:
    """
    Called by the internal alert-checker scheduler endpoint.
    Checks Firestore for active alerts matching region + threshold.
    Publishes to Pub/Sub if threshold is met.
    """
    try:
        fs = _fs()
        alerts = fs.collection(config.ALERTS_COLLECTION)\
            .where("region", "==", region)\
            .where("active", "==", True)\
            .stream()

        async for alert_doc in alerts:
            alert = alert_doc.to_dict()
            threshold = alert.get("threshold_gco2", 9999)

            if current_gco2_kwh <= threshold:
                # Publish to Pub/Sub
                topic_path = _pubsub().topic_path(config.PROJECT_ID, config.ALERT_TOPIC)
                import json as _json
                message = _json.dumps({
                    "alert_id": alert["alert_id"],
                    "region": region,
                    "current_gco2_kwh": current_gco2_kwh,
                    "threshold_gco2_kwh": threshold,
                    "session_id": alert.get("session_id"),
                    "fired_at": datetime.now(timezone.utc).isoformat(),
                }).encode()
                _pubsub().publish(topic_path, message)

                # Update last_fired_at in Firestore
                await alert_doc.reference.update({
                    "last_fired_at": datetime.now(timezone.utc).isoformat()
                })

                logger.info("Alert fired: %s for region %s at %.1f gCO2/kWh",
                            alert["alert_id"], region, current_gco2_kwh)

    except Exception as e:
        logger.error("Alert checker error: %s", e)


###############################################################################
# get_dashboard_insight
###############################################################################

async def get_dashboard_insight(
    vision_description: str,
    current_regions_data: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """
    Grounding tool: given a description of what the agent sees on the dashboard
    (extracted by the Gemini vision stream), return a structured analysis
    for the agent to narrate.

    Args:
        vision_description: Text description of the current dashboard frame.
        current_regions_data: Optional dict of fresh carbon data (from get_carbon_intensity).

    Returns:
        Structured insight the agent should narrate.
    """
    insights = []
    recommendations = []
    anomalies = []

    if current_regions_data:
        regions = current_regions_data.get("regions", {})

        # Find the current best and worst regions visible on screen
        valid = {r: d for r, d in regions.items() if "error" not in d and d.get("current_gco2_kwh")}

        if valid:
            best = min(valid, key=lambda r: valid[r]["current_gco2_kwh"])
            worst = max(valid, key=lambda r: valid[r]["current_gco2_kwh"])
            best_val = valid[best]["current_gco2_kwh"]
            worst_val = valid[worst]["current_gco2_kwh"]

            insights.append(
                f"The dashboard shows {best} is currently the cleanest region "
                f"at {best_val:.0f} gCO₂/kWh."
            )

            if worst_val > 300:
                anomalies.append(
                    f"{worst} is running high at {worst_val:.0f} gCO₂/kWh — "
                    f"likely heavy fossil fuel generation."
                )

            # Check for green windows in forecast
            greenest_window = current_regions_data.get("greenest_window")
            if greenest_window:
                recommendations.append(
                    f"The best upcoming window is {greenest_window['region']} "
                    f"in {greenest_window.get('hours_ahead', '?'):.1f} hours "
                    f"at {greenest_window['gco2_kwh']:.0f} gCO₂/kWh."
                )

            # Renewable flag summary
            green_count = sum(1 for d in valid.values() if d.get("renewable_flag"))
            if green_count > 0:
                insights.append(
                    f"{green_count} of {len(valid)} regions are currently above "
                    f"the {config.RENEWABLE_THRESHOLD_PCT:.0f}% renewable threshold."
                )

    # Acknowledge vision context
    if vision_description:
        insights.insert(0, f"I can see {vision_description.lower().strip('.')}.")

    return {
        "insights": insights,
        "recommendations": recommendations,
        "anomalies": anomalies,
        "narration": " ".join(insights + anomalies + recommendations),
    }
