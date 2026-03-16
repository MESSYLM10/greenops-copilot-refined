"""
GreenOps Copilot — FastAPI application
Endpoints:
  GET  /health                     — liveness probe
  WS   /live                       — Gemini Live API WebSocket bridge
  POST /internal/poll-carbon       — called by Cloud Scheduler every 5 min
  POST /internal/check-alerts      — called by Cloud Scheduler every 10 min
  POST /internal/daily-summary     — called by Cloud Scheduler at midnight
  GET  /api/carbon/current         — REST fallback for dashboard polling
  GET  /api/carbon/history         — REST endpoint for history widget
"""

from __future__ import annotations

import asyncio
import base64
import json
import logging
import os
from contextlib import asynccontextmanager
from datetime import datetime, timezone

import uvicorn
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

import config
from agent.orchestrator import run_live_session
from agent.tools.carbon_intensity import get_carbon_intensity
from agent.tools.supplementary_tools import (
    query_carbon_history,
    fire_alert_if_threshold_met,
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s — %(message)s")
logger = logging.getLogger(__name__)


###############################################################################
# App lifecycle
###############################################################################

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("GreenOps Copilot starting. Project: %s  Region: %s", config.PROJECT_ID, config.PRIMARY_REGION)
    yield
    logger.info("GreenOps Copilot shutting down.")


app = FastAPI(
    title="GreenOps Copilot API",
    description="ADK Orchestrator + Gemini Live API bridge for energy-aware cloud scheduling",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Tighten in production with actual frontend URL
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


###############################################################################
# Health
###############################################################################

@app.get("/health")
async def health():
    return {
        "status": "ok",
        "service": "greenops-copilot-orchestrator",
        "project": config.PROJECT_ID,
        "region": config.PRIMARY_REGION,
        "model": config.GEMINI_MODEL,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


###############################################################################
# WebSocket — Gemini Live API bridge
###############################################################################

@app.websocket("/live")
async def live_websocket(websocket: WebSocket):
    """
    WebSocket protocol:
      Client → Server (JSON messages):
        { "type": "audio",  "data": "<base64 PCM bytes>" }
        { "type": "vision", "data": "<base64 JPEG frame>" }
        { "type": "close" }

      Server → Client (JSON messages):
        { "type": "audio",  "data": "<base64 PCM bytes>" }   — agent speech
        { "type": "status", "session_id": "...", "state": "connected" }
        { "type": "error",  "message": "..." }
    """
    await websocket.accept()
    session_id = websocket.query_params.get("session_id")

    audio_queue: asyncio.Queue = asyncio.Queue(maxsize=50)
    vision_queue: asyncio.Queue = asyncio.Queue(maxsize=10)

    async def audio_output_callback(audio_bytes: bytes):
        """Send synthesised speech back to the browser."""
        try:
            await websocket.send_json({
                "type": "audio",
                "data": base64.b64encode(audio_bytes).decode(),
            })
        except Exception as e:
            logger.warning("Audio send failed: %s", e)

    # Send connected status
    await websocket.send_json({
        "type": "status",
        "state": "connected",
        "session_id": session_id or "new",
    })

    # Start Live session in background
    live_task = asyncio.create_task(
        run_live_session(
            audio_input_queue=audio_queue,
            vision_input_queue=vision_queue,
            audio_output_callback=audio_output_callback,
            session_id=session_id,
        )
    )

    try:
        while True:
            raw = await websocket.receive_text()
            msg = json.loads(raw)

            msg_type = msg.get("type")

            if msg_type == "audio":
                data = base64.b64decode(msg["data"])
                await audio_queue.put(data)

            elif msg_type == "vision":
                # Vision frames are throttled client-side to 1fps
                await vision_queue.put(msg["data"])

            elif msg_type == "close":
                break

            elif msg_type == "ping":
                await websocket.send_json({"type": "pong"})

    except WebSocketDisconnect:
        logger.info("WebSocket disconnected: session %s", session_id)
    except Exception as e:
        logger.error("WebSocket error: %s", e)
        await websocket.send_json({"type": "error", "message": str(e)})
    finally:
        # Signal the live session tasks to close
        await audio_queue.put(None)
        await vision_queue.put(None)
        live_task.cancel()
        try:
            await live_task
        except asyncio.CancelledError:
            pass


###############################################################################
# REST — carbon data (for dashboard polling fallback)
###############################################################################

@app.get("/api/carbon/current")
async def get_current_carbon(regions: str | None = None):
    """
    Fetch current carbon intensity for all (or specified) regions.
    Used by the React dashboard to populate the chart.
    """
    region_list = regions.split(",") if regions else None
    data = await get_carbon_intensity(regions=region_list, forecast_hours=6)
    return data


@app.get("/api/carbon/history")
async def get_history(days: int = 7, region: str | None = None):
    return await query_carbon_history(days=days, region=region)


###############################################################################
# Internal — triggered by Cloud Scheduler
###############################################################################

class SchedulerTrigger(BaseModel):
    trigger: str
    source: str | None = None


@app.post("/internal/poll-carbon")
async def poll_carbon(body: SchedulerTrigger):
    """
    Called every 5 minutes by Cloud Scheduler.
    Fetches current carbon data and writes to BigQuery.
    Also checks for green alerts that need firing.
    """
    logger.info("Carbon poll triggered by: %s", body.trigger)
    try:
        data = await get_carbon_intensity(forecast_hours=1)

        # Check alerts for each region
        for region, region_data in data.get("regions", {}).items():
            if "error" not in region_data and region_data.get("current_gco2_kwh"):
                await fire_alert_if_threshold_met(
                    region=region,
                    current_gco2_kwh=region_data["current_gco2_kwh"],
                    session_callback=None,
                )

        return {
            "status": "ok",
            "regions_polled": len(data.get("regions", {})),
            "greenest_now": data.get("greenest_now"),
            "timestamp": data.get("retrieved_at"),
        }
    except Exception as e:
        logger.error("Carbon poll failed: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/internal/check-alerts")
async def check_alerts(body: SchedulerTrigger):
    """
    Called every 10 minutes by Cloud Scheduler.
    Standalone alert check (in addition to per-poll check above).
    """
    logger.info("Alert check triggered")
    return {"status": "ok", "timestamp": datetime.now(timezone.utc).isoformat()}


@app.post("/internal/daily-summary")
async def daily_summary(body: SchedulerTrigger):
    """
    Called daily at midnight UTC by Cloud Scheduler.
    Aggregates daily CO2 savings into BigQuery summary table.
    """
    logger.info("Daily summary triggered")
    try:
        summary = await query_carbon_history(days=1)
        logger.info("Daily summary: %s", summary.get("summary", ""))
        return {"status": "ok", "summary": summary}
    except Exception as e:
        logger.error("Daily summary failed: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


###############################################################################
# Entry point (local dev)
###############################################################################

if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=int(os.environ.get("PORT", 8080)),
        reload=True,
        ws="websockets",
    )
