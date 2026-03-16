# GreenOps Copilot

> A real-time voice+vision AI agent that schedules cloud workloads to the greenest available GCP region — powered by the Gemini Live API and deployed entirely on Google Cloud.

**Gemini Live Agent Challenge — Live Agents Category**

---

## What it does

GreenOps Copilot lets you manage your cloud carbon footprint by talking to it. You share your screen, speak a workload scheduling request, and the agent:

1. **Sees** your live carbon intensity dashboard (via vision stream)
2. **Reasons** over real-time gCO₂/kWh data from Electricity Maps + GCP Carbon Footprint API
3. **Schedules** your job to the greenest available GCP region within your SLA window
4. **Speaks back** with the decision and estimated CO₂ saved — live, interruptible

---

## Architecture

```
User (voice + screen share)
        ↓
Gemini 2.0 Flash Live API   ←→   ADK Orchestrator (Cloud Run, min 1 instance)
                                         ↓
                              ┌─────────────────────────┐
                              │   Registered ADK Tools  │
                              │ • get_carbon_intensity  │  ← Electricity Maps API
                              │ • schedule_workload     │  ← Cloud Scheduler + Cloud Run Jobs
                              │ • query_carbon_history  │  ← BigQuery
                              │ • set_green_alert       │  ← Cloud Pub/Sub
                              │ • get_dashboard_insight │  ← Vision grounding
                              └─────────────────────────┘
                                         ↓
                              BigQuery · Firestore · Pub/Sub · Cloud Monitoring
```

---

## Prerequisites

- Google Cloud project with billing enabled
- [gcloud CLI](https://cloud.google.com/sdk/install) authenticated
- [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.7
- [Docker](https://docs.docker.com/get-docker/)
- [Electricity Maps API key](https://www.electricitymaps.com/free-tier-api) (free tier: 1,000 req/day)
- [Gemini API key](https://aistudio.google.com/app/apikey)

---

## Quick start (automated — judges use this)

```bash
# 1. Clone the repo
git clone https://github.com/YOUR_USERNAME/greenops-copilot.git
cd greenops-copilot

# 2. Set your GCP project
export PROJECT_ID=your-gcp-project-id
export REGION=us-central1          # optional

# 3. First-time bootstrap (creates state bucket, enables APIs)
make setup

# 4. Store API keys securely in Secret Manager
make secrets

# 5. Full deploy — Terraform + Docker build + push + apply
make deploy

# 6. Open the frontend URL printed at the end
```

The `make deploy` command:
- Enables all required GCP APIs
- Provisions infrastructure via Terraform (Cloud Run, BigQuery, Firestore, Pub/Sub, Cloud Scheduler, Cloud Monitoring)
- Builds and pushes 3 Docker images to Artifact Registry
- Deploys all Cloud Run services
- Runs a smoke test against the orchestrator health endpoint
- Prints the deployed URLs

---

## Manual step-by-step (if you prefer)

```bash
# Infrastructure only
make tf-init
make tf-plan    # review the plan
make tf-apply

# Images only
make build-all
make push-all

# Check status
make status

# Tail logs
make logs
```

---

## Alternatively: use the shell script directly

```bash
export PROJECT_ID=your-gcp-project-id
bash scripts/deploy.sh                 # full deploy
bash scripts/deploy.sh --infra-only    # Terraform only
bash scripts/deploy.sh --images-only   # build & push images only
bash scripts/deploy.sh --destroy       # tear everything down
```

---

## CI/CD — automated deployment on push

Every push to `main` triggers Cloud Build (`cloudbuild.yaml`):

1. Runs Python unit tests
2. Builds and pushes all 3 images
3. Runs `terraform plan` and `terraform apply`
4. Smoke-tests the deployed orchestrator

To connect Cloud Build to this repo:
```bash
gcloud builds triggers create github \
  --repo-name=greenops-copilot \
  --repo-owner=YOUR_USERNAME \
  --branch-pattern=^main$ \
  --build-config=cloudbuild.yaml \
  --project=$PROJECT_ID
```

---

## Project structure

```
greenops-copilot/
├── Makefile                    # Single deployment entrypoint
├── cloudbuild.yaml             # CI/CD pipeline
├── scripts/
│   └── deploy.sh               # Standalone deploy script
├── terraform/
│   ├── main.tf                 # Root — APIs, Artifact Registry, Secrets
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── iam/                # Service accounts + IAM bindings
│       ├── cloudrun/           # Orchestrator, frontend, executor jobs
│       ├── bigquery/           # Carbon dataset + tables
│       ├── firestore/          # Session state + indexes
│       ├── pubsub/             # Alert topics + subscriptions
│       ├── scheduler/          # Carbon polling + alert checker
│       └── monitoring/         # Custom metrics + alerting policies
├── backend/                    # FastAPI + ADK Orchestrator
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── main.py
│   ├── agent/
│   │   ├── tools/
│   │   │   ├── carbon_intensity.py
│   │   │   ├── workload_scheduler.py
│   │   │   ├── carbon_history.py
│   │   │   ├── green_alerts.py
│   │   │   └── dashboard_insight.py
│   │   └── orchestrator.py
│   └── tests/
├── frontend/                   # React + Chart.js dashboard
│   ├── Dockerfile
│   └── src/
└── executor/                   # Cloud Run Job executor
    └── Dockerfile
```

---

## Environment variables

| Variable | Where set | Description |
|---|---|---|
| `ELECTRICITY_MAPS_API_KEY` | Secret Manager | Electricity Maps API key |
| `GEMINI_API_KEY` | Secret Manager | Gemini API key |
| `GCP_PROJECT_ID` | Cloud Run env | GCP project ID |
| `PRIMARY_REGION` | Cloud Run env | Primary region |
| `GREEN_REGIONS` | Cloud Run env | Comma-separated list of candidate regions |
| `BIGQUERY_DATASET` | Cloud Run env | BigQuery dataset ID |
| `GEMINI_MODEL` | Cloud Run env | `gemini-2.0-flash-exp` |

---

## GCP services used

| Service | Purpose |
|---|---|
| Cloud Run | ADK Orchestrator, React frontend, workload executor jobs |
| Artifact Registry | Container image storage |
| BigQuery | Carbon intensity logs, job savings history |
| Firestore | Session state, user preferences, alert configs |
| Cloud Scheduler | Carbon intensity polling (5-min), alert checker (10-min) |
| Cloud Pub/Sub | Async green window alert delivery |
| Cloud Monitoring | Custom gCO₂ metrics, uptime checks, alert policies |
| Secret Manager | API keys |
| Cloud Build | CI/CD pipeline |

---

## Bonus: Infrastructure as Code proof

All GCP resources are managed by Terraform. The Terraform state is stored in a GCS bucket (`$PROJECT_ID-tfstate`). Zero manual console clicks are required after `make setup`.

See `terraform/` for the complete resource definitions.

---

*Submitted to the Gemini Live Agent Challenge — Live Agents Category*
