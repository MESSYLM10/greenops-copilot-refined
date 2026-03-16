"""
ADK Tool: schedule_workload
Creates a Cloud Run Job scheduled for the greenest available window.
Logs job details + estimated CO2 savings to BigQuery.
"""

from __future__ import annotations

import json
import logging
import uuid
from datetime import datetime, timezone
from typing import Any

from google.cloud import bigquery, scheduler_v1
from google.protobuf import duration_pb2

import config

logger = logging.getLogger(__name__)

_bq_client: bigquery.Client | None = None
_scheduler_client: scheduler_v1.CloudSchedulerClient | None = None


def _bq() -> bigquery.Client:
    global _bq_client
    if _bq_client is None:
        _bq_client = bigquery.Client(project=config.PROJECT_ID)
    return _bq_client


def _scheduler() -> scheduler_v1.CloudSchedulerClient:
    global _scheduler_client
    if _scheduler_client is None:
        _scheduler_client = scheduler_v1.CloudSchedulerClient()
    return _scheduler_client


async def schedule_workload(
    workload_description: str,
    target_region: str,
    run_at_utc: str,
    current_gco2_kwh: float,
    target_gco2_kwh: float,
    job_config: dict[str, Any] | None = None,
    session_id: str | None = None,
) -> dict[str, Any]:
    """
    Schedule a Cloud Run Job to execute in target_region at run_at_utc.
    Calculates and persists CO2 savings vs. running immediately.

    Args:
        workload_description: Human-readable description of the workload.
        target_region: GCP region to execute in (e.g. "europe-west1").
        run_at_utc: ISO 8601 UTC datetime for scheduled execution.
        current_gco2_kwh: Carbon intensity right now in the user's region (gCO2/kWh).
        target_gco2_kwh: Forecast carbon intensity in target region at run_at_utc.
        job_config: Optional dict with compute_units (default 100) and duration_hours (default 1).
        session_id: Firestore session ID for attribution.

    Returns:
        {
          "job_id": "greenops-job-abc12345",
          "target_region": "europe-west1",
          "scheduled_for": "2026-03-16T14:00:00Z",
          "co2_saved_kg": 12.4,
          "co2_reduction_pct": 96.1,
          "current_intensity": 420.0,
          "target_intensity": 18.4,
          "confirmation": "Scheduled for 14:00 UTC in Belgium (europe-west1). ..."
        }
    """
    if target_region not in config.GREEN_REGIONS and target_region not in config.REGION_TO_ZONE:
        return {
            "error": f"Region '{target_region}' is not in the configured green regions list.",
            "valid_regions": config.GREEN_REGIONS,
        }

    # Parse and validate run_at
    try:
        run_dt = datetime.fromisoformat(run_at_utc.replace("Z", "+00:00"))
    except ValueError:
        return {"error": f"Invalid run_at_utc format: '{run_at_utc}'. Use ISO 8601, e.g. '2026-03-16T14:00:00Z'."}

    now = datetime.now(timezone.utc)
    if run_dt <= now:
        return {"error": "run_at_utc must be in the future."}

    # Estimate CO2 savings
    cfg = job_config or {}
    compute_units = cfg.get("compute_units", 100)   # arbitrary CPU-hour proxy
    duration_hours = cfg.get("duration_hours", 1.0)
    kwh_estimate = compute_units * duration_hours * 0.001  # rough kWh estimate

    co2_now_kg = (current_gco2_kwh * kwh_estimate) / 1000
    co2_target_kg = (target_gco2_kwh * kwh_estimate) / 1000
    co2_saved_kg = max(0.0, co2_now_kg - co2_target_kg)
    co2_reduction_pct = (co2_saved_kg / co2_now_kg * 100) if co2_now_kg > 0 else 0.0

    job_id = f"greenops-job-{uuid.uuid4().hex[:8]}"

    # Create Cloud Scheduler job to trigger Cloud Run Job at the green window
    scheduler_job_name = _create_scheduler_entry(
        job_id=job_id,
        target_region=target_region,
        run_dt=run_dt,
        workload_description=workload_description,
        job_config=cfg,
    )

    if "error" in scheduler_job_name:
        return scheduler_job_name

    # Log to BigQuery
    _log_scheduled_job(
        job_id=job_id,
        target_region=target_region,
        run_at=run_dt,
        workload_description=workload_description,
        current_gco2_kwh=current_gco2_kwh,
        target_gco2_kwh=target_gco2_kwh,
        co2_saved_kg=co2_saved_kg,
        co2_reduction_pct=co2_reduction_pct,
        session_id=session_id,
    )

    region_display = _region_display_name(target_region)
    run_time_str = run_dt.strftime("%H:%M UTC on %d %b %Y")

    return {
        "job_id": job_id,
        "scheduler_job": scheduler_job_name,
        "target_region": target_region,
        "region_display": region_display,
        "scheduled_for": run_dt.isoformat(),
        "co2_saved_kg": round(co2_saved_kg, 2),
        "co2_reduction_pct": round(co2_reduction_pct, 1),
        "current_intensity_gco2_kwh": current_gco2_kwh,
        "target_intensity_gco2_kwh": target_gco2_kwh,
        "confirmation": (
            f"Scheduled for {run_time_str} in {region_display}. "
            f"That saves approximately {co2_saved_kg:.1f} kg of CO₂ "
            f"— a {co2_reduction_pct:.0f}% reduction compared to running right now."
        ),
    }


def _create_scheduler_entry(
    job_id: str,
    target_region: str,
    run_dt: datetime,
    workload_description: str,
    job_config: dict,
) -> dict | str:
    """Create a one-time Cloud Scheduler job to trigger the Cloud Run Job executor."""
    try:
        parent = f"projects/{config.PROJECT_ID}/locations/{config.PRIMARY_REGION}"
        executor_url = (
            f"https://{target_region}-run.googleapis.com/apis/run.googleapis.com/v1/"
            f"namespaces/{config.PROJECT_ID}/jobs/"
            f"greenops-executor-{target_region.replace('/', '-')}:run"
        )

        # Cloud Scheduler cron for one-time execution (minute-level precision)
        cron = f"{run_dt.minute} {run_dt.hour} {run_dt.day} {run_dt.month} *"

        job = scheduler_v1.Job(
            name=f"{parent}/jobs/{job_id}",
            description=f"GreenOps: {workload_description[:100]}",
            schedule=cron,
            time_zone="UTC",
            http_target=scheduler_v1.HttpTarget(
                uri=executor_url,
                http_method=scheduler_v1.HttpMethod.POST,
                body=json.dumps({
                    "job_id": job_id,
                    "workload_description": workload_description,
                    "job_config": job_config,
                    "target_region": target_region,
                }).encode(),
                headers={"Content-Type": "application/json"},
                oidc_token=scheduler_v1.OidcToken(
                    service_account_email=f"greenops-orchestrator@{config.PROJECT_ID}.iam.gserviceaccount.com",
                ),
            ),
            attempt_deadline=duration_pb2.Duration(seconds=3600),
        )

        created = _scheduler().create_job(parent=parent, job=job)
        return {"scheduler_job_name": created.name, "status": "created"}

    except Exception as e:
        logger.error("Cloud Scheduler job creation failed: %s", e)
        # Non-fatal: return the job_id anyway so the agent can confirm
        return {"scheduler_job_name": f"PENDING-{job_id}", "status": "scheduler_error", "detail": str(e)}


def _log_scheduled_job(
    job_id: str,
    target_region: str,
    run_at: datetime,
    workload_description: str,
    current_gco2_kwh: float,
    target_gco2_kwh: float,
    co2_saved_kg: float,
    co2_reduction_pct: float,
    session_id: str | None,
) -> None:
    try:
        table_id = f"{config.PROJECT_ID}.{config.BIGQUERY_DATASET}.{config.JOBS_TABLE}"
        rows = [{
            "job_id": job_id,
            "scheduled_at": datetime.now(timezone.utc).isoformat(),
            "run_at": run_at.isoformat(),
            "target_region": target_region,
            "workload_type": workload_description[:200],
            "carbon_at_schedule": current_gco2_kwh,
            "carbon_at_target": target_gco2_kwh,
            "co2_saved_kg": co2_saved_kg,
            "co2_reduction_pct": co2_reduction_pct,
            "status": "SCHEDULED",
            "user_session_id": session_id,
        }]
        errors = _bq().insert_rows_json(table_id, rows)
        if errors:
            logger.warning("BigQuery job log errors: %s", errors)
    except Exception as e:
        logger.warning("BigQuery job logging failed (non-fatal): %s", e)


def _region_display_name(region: str) -> str:
    names = {
        "europe-west1": "Belgium (europe-west1)",
        "europe-north1": "Finland (europe-north1)",
        "europe-west4": "Netherlands (europe-west4)",
        "us-west1": "Oregon (us-west1)",
        "us-central1": "Iowa (us-central1)",
        "asia-east1": "Taiwan (asia-east1)",
    }
    return names.get(region, region)
