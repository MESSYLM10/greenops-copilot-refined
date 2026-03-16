"""
GreenOps Copilot — ADK Orchestrator
Uses the new google-genai SDK (google.genai) which replaced google.generativeai.
"""

from __future__ import annotations

import asyncio
import base64
import json
import logging
import uuid
from datetime import datetime, timezone
from typing import Any

from google import genai
from google.genai import types as genai_types
from google.cloud import firestore

import config
from agent.tools.carbon_intensity import get_carbon_intensity
from agent.tools.workload_scheduler import schedule_workload
from agent.tools.supplementary_tools import (
    query_carbon_history,
    set_green_alert,
    get_dashboard_insight,
)

logger = logging.getLogger(__name__)

# Firestore client
_fs_client: firestore.AsyncClient | None = None

def _fs() -> firestore.AsyncClient:
    global _fs_client
    if _fs_client is None:
        _fs_client = firestore.AsyncClient(project=config.PROJECT_ID)
    return _fs_client

###############################################################################
# Tool declarations
###############################################################################

TOOL_DECLARATIONS = [
    genai_types.FunctionDeclaration(
        name="get_carbon_intensity",
        description=(
            "Fetch real-time and forecast carbon intensity (gCO2/kWh) and "
            "renewable percentage for GCP regions. Returns greenest region "
            "right now and best upcoming scheduling window."
        ),
        parameters=genai_types.Schema(
            type=genai_types.Type.OBJECT,
            properties={
                "regions": genai_types.Schema(
                    type=genai_types.Type.ARRAY,
                    items=genai_types.Schema(type=genai_types.Type.STRING),
                    description="GCP region codes. Omit for all configured regions.",
                ),
                "forecast_hours": genai_types.Schema(
                    type=genai_types.Type.INTEGER,
                    description="Hours ahead for forecast (0-12). Default 6.",
                ),
            },
        ),
    ),
    genai_types.FunctionDeclaration(
        name="schedule_workload",
        description=(
            "Schedule a compute workload to run in the greenest GCP region. "
            "Creates a Cloud Scheduler job and logs CO2 savings."
        ),
        parameters=genai_types.Schema(
            type=genai_types.Type.OBJECT,
            required=["workload_description", "target_region", "run_at_utc",
                      "current_gco2_kwh", "target_gco2_kwh"],
            properties={
                "workload_description": genai_types.Schema(
                    type=genai_types.Type.STRING,
                    description="Human-readable description of the workload.",
                ),
                "target_region": genai_types.Schema(
                    type=genai_types.Type.STRING,
                    description="GCP region code (e.g. 'europe-west1').",
                ),
                "run_at_utc": genai_types.Schema(
                    type=genai_types.Type.STRING,
                    description="ISO 8601 UTC datetime (e.g. '2026-03-16T14:00:00Z').",
                ),
                "current_gco2_kwh": genai_types.Schema(
                    type=genai_types.Type.NUMBER,
                    description="Current carbon intensity in user's region.",
                ),
                "target_gco2_kwh": genai_types.Schema(
                    type=genai_types.Type.NUMBER,
                    description="Forecast intensity in target region at run_at_utc.",
                ),
            },
        ),
    ),
    genai_types.FunctionDeclaration(
        name="query_carbon_history",
        description="Query historical carbon savings from BigQuery.",
        parameters=genai_types.Schema(
            type=genai_types.Type.OBJECT,
            properties={
                "days": genai_types.Schema(
                    type=genai_types.Type.INTEGER,
                    description="Days of history (1-90). Default 7.",
                ),
                "region": genai_types.Schema(
                    type=genai_types.Type.STRING,
                    description="Optional region filter.",
                ),
            },
        ),
    ),
    genai_types.FunctionDeclaration(
        name="set_green_alert",
        description="Create an alert that fires when a region drops below a carbon threshold.",
        parameters=genai_types.Schema(
            type=genai_types.Type.OBJECT,
            required=["region", "threshold_gco2_kwh", "session_id"],
            properties={
                "region": genai_types.Schema(
                    type=genai_types.Type.STRING,
                    description="GCP region to monitor.",
                ),
                "threshold_gco2_kwh": genai_types.Schema(
                    type=genai_types.Type.NUMBER,
                    description="Alert threshold in gCO2/kWh.",
                ),
                "session_id": genai_types.Schema(
                    type=genai_types.Type.STRING,
                    description="Current session ID for alert routing.",
                ),
            },
        ),
    ),
    genai_types.FunctionDeclaration(
        name="get_dashboard_insight",
        description="Analyse the carbon dashboard visible on screen and return narration.",
        parameters=genai_types.Schema(
            type=genai_types.Type.OBJECT,
            properties={
                "vision_description": genai_types.Schema(
                    type=genai_types.Type.STRING,
                    description="Brief description of what the vision stream shows.",
                ),
            },
        ),
    ),
]

TOOLS = [genai_types.Tool(function_declarations=TOOL_DECLARATIONS)]

###############################################################################
# Tool dispatcher
###############################################################################

TOOL_HANDLERS = {
    "get_carbon_intensity":  get_carbon_intensity,
    "schedule_workload":     schedule_workload,
    "query_carbon_history":  query_carbon_history,
    "set_green_alert":       set_green_alert,
    "get_dashboard_insight": get_dashboard_insight,
}


async def dispatch_tool(function_call: Any, session_id: str) -> Any:
    name = function_call.name
    args = dict(function_call.args or {})
    if name == "set_green_alert":
        args["session_id"] = session_id
    handler = TOOL_HANDLERS.get(name)
    if not handler:
        return {"error": f"Unknown tool: {name}"}
    try:
        result = await handler(**args)
        logger.info("Tool %s -> %s", name, str(result)[:200])
        return result
    except Exception as e:
        logger.error("Tool error (%s): %s", name, e)
        return {"error": str(e)}

###############################################################################
# Session state
###############################################################################

async def load_session(session_id: str) -> dict:
    try:
        doc = await _fs().collection(config.FIRESTORE_COLLECTION).document(session_id).get()
        return doc.to_dict() or {}
    except Exception as e:
        logger.warning("Session load failed: %s", e)
        return {}


async def save_session(session_id: str, state: dict) -> None:
    try:
        state["updated_at"] = datetime.now(timezone.utc).isoformat()
        await _fs().collection(config.FIRESTORE_COLLECTION).document(session_id).set(
            state, merge=True
        )
    except Exception as e:
        logger.warning("Session save failed: %s", e)

###############################################################################
# Live API session
###############################################################################

async def run_live_session(
    audio_input_queue: asyncio.Queue,
    vision_input_queue: asyncio.Queue,
    audio_output_callback,
    session_id: str | None = None,
) -> None:
    if session_id is None:
        session_id = str(uuid.uuid4())

    session_state = await load_session(session_id)
    logger.info("Live session started: %s", session_id)

    client = genai.Client(api_key=config.GEMINI_API_KEY)

    live_config = genai_types.LiveConnectConfig(
        response_modalities=["AUDIO"],
        system_instruction=config.SYSTEM_PROMPT,
        tools=TOOLS,
        speech_config=genai_types.SpeechConfig(
            voice_config=genai_types.VoiceConfig(
                prebuilt_voice_config=genai_types.PrebuiltVoiceConfig(
                    voice_name="Aoede"
                )
            )
        ),
    )

    async with client.aio.live.connect(
        model=config.GEMINI_MODEL,
        config=live_config,
    ) as live_session:

        if session_state.get("history_summary"):
            await live_session.send(
                input=f"[Session context: {session_state['history_summary']}]",
                end_of_turn=False,
            )

        async def send_audio_task():
            while True:
                chunk = await audio_input_queue.get()
                if chunk is None:
                    break
                await live_session.send(
                    input=genai_types.LiveClientRealtimeInput(
                        media_chunks=[
                            genai_types.Blob(
                                data=chunk,
                                mime_type="audio/pcm;rate=16000"
                            )
                        ]
                    )
                )

        async def send_vision_task():
            while True:
                frame_b64 = await vision_input_queue.get()
                if frame_b64 is None:
                    break
                frame_bytes = base64.b64decode(frame_b64)
                await live_session.send(
                    input=genai_types.LiveClientRealtimeInput(
                        media_chunks=[
                            genai_types.Blob(
                                data=frame_bytes,
                                mime_type="image/jpeg"
                            )
                        ]
                    )
                )

        async def receive_task():
            async for response in live_session.receive():
                if response.data:
                    await audio_output_callback(response.data)

                if response.tool_call:
                    for fc in response.tool_call.function_calls:
                        result = await dispatch_tool(fc, session_id)
                        await live_session.send(
                            input=genai_types.LiveClientToolResponse(
                                function_responses=[
                                    genai_types.FunctionResponse(
                                        id=fc.id,
                                        name=fc.name,
                                        response={"result": result},
                                    )
                                ]
                            )
                        )

                if response.server_content and response.server_content.turn_complete:
                    await save_session(session_id, {
                        "session_id": session_id,
                        "last_active": datetime.now(timezone.utc).isoformat(),
                    })

        try:
            await asyncio.gather(
                send_audio_task(),
                send_vision_task(),
                receive_task(),
            )
        except asyncio.CancelledError:
            logger.info("Live session %s cancelled.", session_id)
        except Exception as e:
            logger.error("Live session %s error: %s", session_id, e)
            raise
        finally:
            await save_session(session_id, {"status": "disconnected"})
