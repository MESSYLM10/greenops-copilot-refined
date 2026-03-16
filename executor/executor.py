"""
GreenOps Copilot — Cloud Run Job Executor
Runs the scheduled workload in the target green region.
Publishes COMPLETE / FAILED event to Pub/Sub on completion.
"""

import json
import logging
import os
import sys
from datetime import datetime, timezone

from google.cloud import pubsub_v1

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PROJECT_ID = os.environ["GCP_PROJECT_ID"]
EXECUTION_REGION = os.environ.get("EXECUTION_REGION", "unknown")
JOB_EVENTS_TOPIC = os.environ.get("JOB_EVENTS_TOPIC", "greenops-job-events")

# Payload injected by Cloud Scheduler (set via environment in production)
JOB_ID = os.environ.get("JOB_ID", "unknown")
WORKLOAD_DESCRIPTION = os.environ.get("WORKLOAD_DESCRIPTION", "unspecified workload")


def publish_event(status: str, detail: dict = None):
    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(PROJECT_ID, JOB_EVENTS_TOPIC)
    payload = json.dumps({
        "job_id": JOB_ID,
        "status": status,
        "execution_region": EXECUTION_REGION,
        "completed_at": datetime.now(timezone.utc).isoformat(),
        "workload_description": WORKLOAD_DESCRIPTION,
        **(detail or {}),
    }).encode()
    publisher.publish(topic_path, payload)
    logger.info("Published %s event for job %s", status, JOB_ID)


def main():
    logger.info(
        "Executor starting. Job: %s  Region: %s  Workload: %s",
        JOB_ID, EXECUTION_REGION, WORKLOAD_DESCRIPTION,
    )

    try:
        # ── Execute the actual workload here ────────────────────────────────
        # In production this would run the user's batch job.
        # For the hackathon demo, we simulate a compute task.
        import time
        logger.info("Running workload: %s", WORKLOAD_DESCRIPTION)
        time.sleep(2)  # Simulate compute
        logger.info("Workload complete.")
        # ────────────────────────────────────────────────────────────────────

        publish_event("COMPLETE")
        sys.exit(0)

    except Exception as e:
        logger.error("Workload failed: %s", e)
        publish_event("FAILED", {"error": str(e)})
        sys.exit(1)


if __name__ == "__main__":
    main()
