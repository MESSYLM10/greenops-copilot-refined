GREENOPS COPILOT — DEVPOST SUBMISSION TEXT
Gemini Live Agent Challenge | Live Agents Category
────────────────────────────────────────────────────────────────────────────────
COPY AND PASTE EACH SECTION INTO THE DEVPOST FORM FIELDS
────────────────────────────────────────────────────────────────────────────────


PROJECT NAME
────────────
GreenOps Copilot


SHORT TAGLINE  (150 chars max)
────────────────────────────────
A voice+vision AI agent that schedules cloud workloads to the greenest GCP region — live, interruptible, grounded in real carbon data.


WHAT IT DOES  (project description — ~300 words)
──────────────────────────────────────────────────
GreenOps Copilot is a real-time, multimodal AI agent that transforms how engineering teams manage cloud carbon footprints. Instead of scheduling compute jobs based on cost or latency alone, the agent optimises for carbon intensity — measured in gCO₂ per kilowatt-hour.

The interaction model is genuinely live. A user shares their screen, showing the GreenOps carbon intensity dashboard. The agent sees the dashboard through the Gemini Live API vision stream. The user speaks naturally — asking about current grid conditions, requesting workload scheduling, or setting green window alerts. The agent responds in real time, can be interrupted mid-sentence, and grounds every numeric claim in live tool call results.

The core workflow: a user says "we have 50,000 documents to vectorise — find the greenest window in the next six hours." The agent calls the Electricity Maps API across all configured GCP regions, identifies that Finland will reach 12 gCO₂/kWh at 14:00 UTC on wind surplus, and schedules the Cloud Run Job there — confirming "that saves 18 kilograms of CO₂, a 97% reduction compared to running it now."

Beyond reactive scheduling, the agent monitors actively. When a region drops below a user-set carbon threshold, it fires a Pub/Sub alert and speaks proactively — the user doesn't need to check; the agent tells them.

The architecture follows a clean separation: the Gemini Live API handles all real-time audio and vision I/O; the ADK Orchestrator (Cloud Run) registers five tools and dispatches them; BigQuery stores carbon history and job savings; Cloud Scheduler manages the green-window execution queue; Cloud Monitoring tracks cumulative CO₂ saved as a custom metric. All infrastructure is Terraform-managed with a single `make deploy` entrypoint.

GreenOps Copilot was built by Johnson Sikhumbuzo Dlamini, a Lecturer in Computer Science at the University of Eswatini (UNESWA) and Principal Investigator on Project MAAI, a climate research initiative. The system has direct applications in the African context, where load-shedding schedules in South Africa and Eswatini create natural green windows aligned with renewable surplus periods.


HOW WE BUILT IT  (~200 words)
──────────────────────────────
The backend is a FastAPI service deployed on Cloud Run, built around the Google ADK (Agent Development Kit). Five tools are registered as Gemini function declarations:

1. get_carbon_intensity — fetches real-time and 6-hour forecast gCO₂/kWh from the Electricity Maps API for all six configured GCP regions, writes to BigQuery
2. schedule_workload — creates Cloud Scheduler jobs targeting green-region Cloud Run Job executors, logs CO₂ savings
3. query_carbon_history — BigQuery queries for historical savings and trends
4. set_green_alert — Firestore-backed alert subscriptions, delivered via Pub/Sub
5. get_dashboard_insight — grounding tool that structures what the vision stream observes into narration

The Gemini Live API WebSocket bridge accepts PCM audio from the browser mic and JPEG frames from screen-share (throttled to 1fps), feeds both into a bidirectional gemini-2.0-flash-exp session, and plays audio output back through the Web Audio API. Flash was chosen deliberately — its lower token cost means the orchestration layer itself has a smaller carbon footprint.

The React frontend serves the live Chart.js carbon intensity dashboard, handles WebRTC screen capture, and updates the savings counter and job queue in real time.

All infrastructure is provisioned by Terraform across 7 modules (Cloud Run, BigQuery, Firestore, Pub/Sub, Scheduler, Monitoring, IAM). CI/CD runs on Cloud Build, triggered on push to main.


CHALLENGES WE RAN INTO  (~150 words)
──────────────────────────────────────
The hardest problem was making interruption feel natural. The Gemini Live API supports true barge-in, but the WebSocket bridge needed careful queue management to drain in-flight audio output immediately when new mic input arrives — otherwise the agent would keep speaking over the user's interruption for several seconds.

The second challenge was grounding. Carbon intensity data moves quickly, and the temptation is to let the model estimate or extrapolate. We addressed this by giving the agent explicit system instructions to never state carbon figures without citing a tool call result, and by validating in every tool response that numeric fields came from the API rather than the model's prior knowledge.

The third was the vision layer. Screen-share frames at even 1fps produce substantial WebSocket traffic. JPEG compression at 60% quality and throttling on the client side kept the connection stable while still giving the model enough visual context to narrate the dashboard accurately.


ACCOMPLISHMENTS  (~100 words)
──────────────────────────────
The canonical interaction — speak a workload request, get interrupted by the agent, interrupt back, receive a confirmed scheduled job with quantified CO₂ savings, and see it appear in Cloud Scheduler — works end-to-end in a single voice session. The agent never states a carbon figure it didn't retrieve from a tool call. The vision narration correctly identifies the greenest region from the dashboard without any text input from the user. And the entire system deploys from zero with a single `make deploy` command.


WHAT WE LEARNED  (~100 words)
──────────────────────────────
The Gemini Live API's function calling within a streaming session is genuinely different from the request/response model — tool calls happen asynchronously mid-conversation, and the model resumes speaking naturally after receiving the result, with no perceptible gap. This changes the design pattern for agentic voice UIs considerably: tools need to be fast (under 2 seconds ideally) and must return structured data the model can narrate directly, not pages of JSON it has to summarise. We also learned that Flash is the right model for this category — not because Pro is unavailable, but because using a smaller model for orchestration is itself a sustainability decision, and that alignment with the product's purpose matters.


WHAT'S NEXT  (~100 words)
───────────────────────────
Direct integration with cloud billing APIs to move from estimated to actual CO₂ per job. Multi-user session support so a whole ops team can share one GreenOps Copilot instance. A mobile companion that sends push notifications when green windows open. And a southern-Africa grid extension — integrating Eskom and ESCOM (Eswatini Electricity) real-time generation data, so the agent can advise on load-shedding-aware scheduling for teams operating in the region. The broader vision is a GreenOps standard — where carbon-aware scheduling is as automatic as autoscaling, and every cloud team has an agent that makes sustainability the path of least resistance.


TECHNOLOGIES USED  (tag field — enter each separately)
────────────────────────────────────────────────────────
Gemini Live API
Google ADK (Agent Development Kit)
gemini-2.0-flash-exp
Google Cloud Run
Google Cloud BigQuery
Google Cloud Firestore
Google Cloud Pub/Sub
Google Cloud Scheduler
Google Cloud Monitoring
Google Cloud Build
Artifact Registry
Terraform
FastAPI
Python
React
Chart.js
Electricity Maps API
WebRTC
WebSockets
Web Audio API


CATEGORY
─────────
Live Agents


PUBLIC CODE REPOSITORY
───────────────────────
https://github.com/YOUR_USERNAME/greenops-copilot


BUILT WITH (technology tags)
──────────────────────────────
python, fastapi, react, terraform, google-cloud, gemini, adk, bigquery, firestore, websockets


PROOF OF GOOGLE CLOUD DEPLOYMENT
──────────────────────────────────
[Link to the 60-second deployment proof screen recording showing:
 Cloud Run services list, Cloud Build logs with terraform apply step,
 Cloud Scheduler job created by the demo, BigQuery table with live rows]
