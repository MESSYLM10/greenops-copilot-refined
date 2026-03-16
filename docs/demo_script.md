GREENOPS COPILOT — DEMO VIDEO SCRIPT
Gemini Live Agent Challenge | Live Agents Category
Target length: 3 min 45 sec | Recorded with OBS or Loom

────────────────────────────────────────────────────────────────────────────────
SEGMENT 1 — PROBLEM STATEMENT  [0:00 – 0:35]
────────────────────────────────────────────────────────────────────────────────
SCREEN: Slide or fullscreen text overlay on dark background.

NARRATION (voiceover or on-camera):
  "By 2026, data centres consume more electricity than most nations.
   AI workloads are making it worse — but most engineers still schedule
   compute jobs the moment they hit enter, regardless of whether the grid
   is running on wind or coal.

   GreenOps Copilot changes that. It's a live AI agent that sees your
   cloud carbon dashboard, hears your scheduling requests, and automatically
   moves your workloads to the cleanest available region — saving real CO₂."

CUT TO: The deployed frontend URL loading in Chrome.

────────────────────────────────────────────────────────────────────────────────
SEGMENT 2 — LIVE DASHBOARD WALKTHROUGH  [0:35 – 1:10]
────────────────────────────────────────────────────────────────────────────────
SCREEN: GreenOps Copilot dashboard — bar chart visible with 6 regions,
        Belgium highlighted green at ~30 gCO₂/kWh, Iowa orange at ~380.

NARRATION (on-camera or voiceover):
  "This is the live carbon intensity dashboard. Each bar shows the current
   gCO₂ per kilowatt-hour for a GCP region, updated every minute from the
   Electricity Maps API. Green means renewable-heavy. Orange means fossil-heavy."

ACTION: Point to Belgium bar, then Iowa bar.

NARRATION:
  "Right now, Belgium is running at 30 gCO₂/kWh — mostly wind.
   Iowa is at 380. If I schedule a batch job in Iowa right now,
   it's thirteen times dirtier than scheduling it in Belgium."

────────────────────────────────────────────────────────────────────────────────
SEGMENT 3 — VOICE + VISION: AGENT NARRATES THE DASHBOARD  [1:10 – 1:50]
────────────────────────────────────────────────────────────────────────────────
SCREEN: Click "Start session" button. Screen share dialog appears — select
        the dashboard tab. Mic indicator turns green.

ACTION (speak to the agent):
  "Hey, can you describe what you're seeing on the dashboard right now?"

WAIT: Agent state indicator shows "Thinking…" then "Speaking…"

EXPECTED AGENT RESPONSE (spoken aloud):
  "I can see the carbon intensity chart showing six GCP regions.
   Belgium is currently the cleanest at around 30 gCO₂ per kilowatt-hour,
   with roughly 88 percent renewable generation. Iowa is the highest at
   about 380 — that's largely coal and gas right now. Finland and Oregon
   are also looking good. If you have any batch work to schedule,
   this is a strong window for Europe."

NARRATION (voiceover over the agent speaking):
  "The agent sees the dashboard through the screen share — no API call
   to describe it. It narrates what it observes, grounded in live data."

────────────────────────────────────────────────────────────────────────────────
SEGMENT 4 — CORE DEMO: SCHEDULING A WORKLOAD  [1:50 – 2:50]
────────────────────────────────────────────────────────────────────────────────
SCREEN: Dashboard + voice indicator visible.

ACTION (speak, then INTERRUPT mid-response):
  "We have about 50,000 documents to vectorise. Check the grid and
   schedule it for the greenest window in the next six hours."

WAIT: Agent calls get_carbon_intensity (tool call indicator visible briefly).

AGENT RESPONSE (spoken, partial — then interrupt):
  "I'm checking the forecast for all six regions now. Belgium is
   showing a strong wind surplus arriving at —"

ACTION (interrupt):
  "— actually, can you also check if Finland has a better window?"

AGENT RESPONSE (picks up cleanly after interruption):
  "Of course. Finland is projecting 12 gCO₂ per kilowatt-hour at 14:00 UTC —
   that's even cleaner than Belgium. I'll schedule the vectorisation job
   there instead.

   Done. I've scheduled your 50,000-document vectorisation job in Finland
   at 14:00 UTC today. That saves approximately 18 kilograms of CO₂
   compared to running it now in your current region —
   a 97 percent reduction in carbon intensity."

SCREEN: Job appears in the "Scheduled jobs" panel on the right.
        Savings counter increments.

NARRATION (voiceover):
  "The agent called two tools: get_carbon_intensity to fetch the forecast,
   and schedule_workload to create the Cloud Run Job and Cloud Scheduler entry.
   The job is now live in GCP."

────────────────────────────────────────────────────────────────────────────────
SEGMENT 5 — GCP DEPLOYMENT PROOF  [2:50 – 3:20]
────────────────────────────────────────────────────────────────────────────────
SCREEN: Switch to GCP Console — Cloud Run services list.

SHOW:
  - greenops-orchestrator service (min 1 instance, healthy)
  - greenops-frontend service

SCREEN: Switch to Cloud Scheduler — show the newly created job
  (greenops-job-XXXXXXXX, schedule pointing to europe-north1, 14:00 UTC).

SCREEN: Switch to BigQuery — greenops_carbon dataset,
  scheduled_jobs table, most recent row visible with co2_saved_kg filled.

SCREEN: Briefly show Cloud Monitoring — custom metric
  "greenops/co2_saved_kg" trending upward.

NARRATION:
  "The entire backend is deployed on Google Cloud Run, provisioned
   with Terraform. The scheduled job is in Cloud Scheduler.
   The CO₂ savings are logged to BigQuery in real time."

────────────────────────────────────────────────────────────────────────────────
SEGMENT 6 — CLOSE  [3:20 – 3:45]
────────────────────────────────────────────────────────────────────────────────
SCREEN: Return to dashboard. Savings counter visible.

NARRATION:
  "GreenOps Copilot is built on the Gemini Live API with the ADK,
   deployed on Google Cloud. It sees your infrastructure, hears your
   intent, and makes sustainability the default — not an afterthought.

   The code, Terraform, and architecture diagram are all in the
   public repository linked below."

FADE OUT.

────────────────────────────────────────────────────────────────────────────────
RECORDING CHECKLIST
────────────────────────────────────────────────────────────────────────────────
Before recording:
  [ ] Frontend deployed and loading real data (not mock)
  [ ] Belgium / Finland intensity below 100 gCO₂/kWh (check Electricity Maps)
  [ ] Mic tested — no echo, no background noise
  [ ] Screen at 1920×1080, browser zoom at 100%
  [ ] Cloud Run services showing healthy (green dot in console)
  [ ] BigQuery dataset has at least one row in carbon_intensity_log

Separate deployment proof clip (60 sec, required by judges):
  [ ] Open Cloud Run console — show both services running
  [ ] Open Cloud Build — show latest successful build with Terraform apply step
  [ ] Open Artifact Registry — show orchestrator:latest image
  [ ] Optionally: terminal showing `make deploy` completing with URLs printed

Upload:
  [ ] Demo video (< 4 min) → Devpost video field
  [ ] Deployment proof (< 2 min) → separate upload or YouTube unlisted
  [ ] Architecture diagram screenshot → Devpost image carousel
