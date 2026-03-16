#!/usr/bin/env bash
###############################################################################
# GreenOps Copilot — bootstrap.sh
#
# Run this ONCE from GCP Cloud Shell before triggering Cloud Build.
# It creates the resources that Cloud Build depends on:
#   - tfstate GCS bucket
#   - Artifact Registry repo (so Cloud Build can push images)
#   - Build artifacts bucket
#   - Required APIs
#   - Cloud Build SA IAM permissions
#
# Usage (Cloud Shell):
#   export PROJECT_ID=your-gcp-project-id
#   bash scripts/bootstrap.sh
###############################################################################

set -euo pipefail

PROJECT_ID="${PROJECT_ID:?ERROR: set PROJECT_ID first — export PROJECT_ID=your-project-id}"
REGION="${REGION:-us-central1}"
TFSTATE_BUCKET="${PROJECT_ID}-tfstate"
ARTIFACTS_BUCKET="${PROJECT_ID}-build-artifacts"

GREEN='\033[1;32m'; BLUE='\033[1;34m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; NC='\033[0m'
step()  { echo -e "\n${BLUE}▶ $*${NC}"; }
ok()    { echo -e "  ${GREEN}✔ $*${NC}"; }
warn()  { echo -e "  ${YELLOW}⚠ $*${NC}"; }

###############################################################################
step "1/7 — Verifying authentication"
###############################################################################
gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 || {
  echo -e "${RED}Not authenticated. Run: gcloud auth login${NC}"
  exit 1
}
gcloud config set project "$PROJECT_ID" --quiet
ok "Authenticated. Project set to: $PROJECT_ID"

###############################################################################
step "2/7 — Enabling required APIs (~3 min on first run)"
###############################################################################
APIS=(
  cloudresourcemanager.googleapis.com
  iam.googleapis.com
  artifactregistry.googleapis.com
  storage.googleapis.com
  cloudbuild.googleapis.com
  run.googleapis.com
  bigquery.googleapis.com
  firestore.googleapis.com
  pubsub.googleapis.com
  cloudscheduler.googleapis.com
  monitoring.googleapis.com
  secretmanager.googleapis.com
  generativelanguage.googleapis.com
  aiplatform.googleapis.com
)

gcloud services enable "${APIS[@]}" --project="$PROJECT_ID" --quiet
ok "APIs enabled."

###############################################################################
step "3/7 — Creating Terraform state bucket"
###############################################################################
if gsutil ls "gs://${TFSTATE_BUCKET}" >/dev/null 2>&1; then
  ok "State bucket already exists: gs://${TFSTATE_BUCKET}"
else
  gsutil mb -p "$PROJECT_ID" -l "$REGION" "gs://${TFSTATE_BUCKET}"
  gsutil versioning set on "gs://${TFSTATE_BUCKET}"
  ok "Created: gs://${TFSTATE_BUCKET} (versioning on)"
fi

###############################################################################
step "4/7 — Creating build artifacts bucket"
###############################################################################
if gsutil ls "gs://${ARTIFACTS_BUCKET}" >/dev/null 2>&1; then
  ok "Artifacts bucket already exists."
else
  gsutil mb -p "$PROJECT_ID" -l "$REGION" "gs://${ARTIFACTS_BUCKET}"
  ok "Created: gs://${ARTIFACTS_BUCKET}"
fi

###############################################################################
step "5/7 — Creating Artifact Registry repository"
###############################################################################
if gcloud artifacts repositories describe greenops-copilot \
     --location="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  ok "Artifact Registry repo already exists."
else
  gcloud artifacts repositories create greenops-copilot \
    --repository-format=docker \
    --location="$REGION" \
    --description="GreenOps Copilot container images" \
    --project="$PROJECT_ID"
  ok "Created Artifact Registry repo: greenops-copilot"
fi

###############################################################################
step "6/7 — Granting Cloud Build service account permissions"
###############################################################################

# Get the default Cloud Build SA
CB_SA="$(gcloud projects describe "$PROJECT_ID" \
  --format='value(projectNumber)')@cloudbuild.gserviceaccount.com"

echo "  Cloud Build SA: $CB_SA"

ROLES=(
  roles/run.admin
  roles/artifactregistry.writer
  roles/iam.serviceAccountUser
  roles/secretmanager.secretAccessor
  roles/logging.logWriter
  roles/storage.objectAdmin
  roles/bigquery.admin
  roles/datastore.owner
  roles/pubsub.admin
  roles/cloudscheduler.admin
  roles/monitoring.admin
)

for ROLE in "${ROLES[@]}"; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$CB_SA" \
    --role="$ROLE" \
    --quiet 2>/dev/null
  echo "    + $ROLE"
done

# Also allow Cloud Build to act as the orchestrator SA (created by Terraform)
# We pre-create it here so Cloud Build can impersonate it
if ! gcloud iam service-accounts describe \
     "greenops-orchestrator@${PROJECT_ID}.iam.gserviceaccount.com" \
     --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud iam service-accounts create greenops-orchestrator \
    --display-name="GreenOps ADK Orchestrator" \
    --project="$PROJECT_ID"
  ok "Pre-created orchestrator SA (Terraform will manage its roles)."
fi

gcloud iam service-accounts add-iam-policy-binding \
  "greenops-orchestrator@${PROJECT_ID}.iam.gserviceaccount.com" \
  --member="serviceAccount:$CB_SA" \
  --role="roles/iam.serviceAccountUser" \
  --project="$PROJECT_ID" --quiet

ok "Cloud Build SA permissions granted."

###############################################################################
step "7/7 — Storing API keys in Secret Manager"
###############################################################################

create_and_store_secret() {
  local SECRET_ID="$1"
  local KEY_VALUE="$2"

  if ! gcloud secrets describe "$SECRET_ID" \
       --project="$PROJECT_ID" >/dev/null 2>&1; then
    gcloud secrets create "$SECRET_ID" \
      --replication-policy=automatic \
      --project="$PROJECT_ID" --quiet
  fi

  if gcloud secrets versions list "$SECRET_ID" \
       --project="$PROJECT_ID" --format="value(name)" 2>/dev/null | grep -q .; then
    warn "Secret '$SECRET_ID' already exists — skipping. To update: echo -n 'NEW_KEY' | gcloud secrets versions add $SECRET_ID --data-file=-"
    return
  fi

  printf '%s' "$KEY_VALUE" | \
    gcloud secrets versions add "$SECRET_ID" \
      --data-file=- --project="$PROJECT_ID"
  ok "Stored: $SECRET_ID"
}

echo ""
echo -e "  ${YELLOW}Carbon data provider setup${NC}"
echo ""
echo "  GreenOps Copilot supports three carbon data providers (in priority order):"
echo ""
echo -e "  ${GREEN}Option 1 — WattTime (RECOMMENDED — free, immediate key)${NC}"
echo "    Sign up at: https://watttime.org/sign-up"
echo "    You get credentials by email within 1-2 minutes."
echo ""
echo -e "  ${YELLOW}Option 2 — Electricity Maps (free tier, key may take time)${NC}"
echo "    Sign up at: https://www.electricitymaps.com/free-tier-api"
echo ""
echo -e "  ${BLUE}Option 3 — Simulation (no key — works immediately)${NC}"
echo "    Realistic regional model. Clearly labeled as simulated in all responses."
echo "    Use this to get the demo running right away."
echo ""

read -r -p "  Which provider do you want to set up? [1/2/3, default=3]: " PROVIDER_CHOICE
PROVIDER_CHOICE="${PROVIDER_CHOICE:-3}"

case "$PROVIDER_CHOICE" in
  1)
    echo ""
    echo "  Go to https://watttime.org/sign-up, create a free account."
    echo "  You will receive an email with your username and password."
    echo ""
    read -r -p "  WattTime username: " WT_USER
    read -r -s -p "  WattTime password (hidden): " WT_PASS
    echo ""

    if [ -n "$WT_USER" ] && [ -n "$WT_PASS" ]; then
      create_and_store_secret "watttime-username" "$WT_USER"
      create_and_store_secret "watttime-password" "$WT_PASS"

      # Set CARBON_PROVIDER to watttime
      create_and_store_secret "carbon-provider" "watttime"
      ok "WattTime credentials stored. Provider set to: watttime"
    else
      warn "Empty credentials — falling back to simulation mode."
      create_and_store_secret "carbon-provider" "simulation"
    fi
    ;;
  2)
    echo ""
    read -r -s -p "  Electricity Maps API key (hidden): " EM_KEY
    echo ""

    if [ -n "$EM_KEY" ]; then
      create_and_store_secret "electricity-maps-api-key" "$EM_KEY"
      create_and_store_secret "carbon-provider" "electricity_maps"
      ok "Electricity Maps key stored. Provider set to: electricity_maps"
    else
      warn "Empty key — falling back to simulation mode."
      create_and_store_secret "carbon-provider" "simulation"
    fi
    ;;
  *)
    echo ""
    echo -e "  ${BLUE}Using simulation mode — no API key required.${NC}"
    echo "  Data will be clearly labeled 'simulated' in all API responses."
    echo "  You can add a real provider later by updating the secret:"
    echo "    echo -n 'watttime' | gcloud secrets versions add carbon-provider --data-file=-"
    echo "    echo -n 'USERNAME' | gcloud secrets versions add watttime-username --data-file=-"
    echo "    echo -n 'PASSWORD' | gcloud secrets versions add watttime-password --data-file=-"
    create_and_store_secret "carbon-provider" "simulation"
    ok "Simulation mode configured."
    ;;
esac

# Gemini API key (always required)
echo ""
read -r -s -p "  Gemini API key — from aistudio.google.com/app/apikey (hidden): " GEMINI_KEY
echo ""
if [ -n "$GEMINI_KEY" ]; then
  create_and_store_secret "gemini-api-key" "$GEMINI_KEY"
else
  warn "No Gemini key provided. The Live API session will not work without it."
fi

###############################################################################
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Bootstrap complete.${NC}"
echo ""
echo -e "  Next step — push code to GitHub, then run:"
echo ""
echo -e "  ${BLUE}gcloud builds submit . \\${NC}"
echo -e "  ${BLUE}  --config=cloudbuild.yaml \\${NC}"
echo -e "  ${BLUE}  --substitutions=SHORT_SHA=\$(git rev-parse --short HEAD),_REGION=${REGION}${NC}"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
