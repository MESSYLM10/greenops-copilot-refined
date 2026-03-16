#!/usr/bin/env bash
###############################################################################
# GreenOps Copilot — deploy.sh
# Standalone deployment script (no make required).
# Proves automated Cloud deployment for hackathon judges.
#
# Usage:
#   export PROJECT_ID=your-gcp-project-id
#   export REGION=us-central1          # optional, defaults to us-central1
#   bash scripts/deploy.sh [--infra-only | --images-only | --destroy]
#
###############################################################################

set -euo pipefail

###############################################################################
# Config
###############################################################################
PROJECT_ID="${PROJECT_ID:?ERROR: set PROJECT_ID environment variable}"
REGION="${REGION:-us-central1}"
IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD 2>/dev/null || echo "latest")}"
REGISTRY="${REGION}-docker.pkg.dev/${PROJECT_ID}/greenops-copilot"
TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/terraform"
MODE="${1:-full}"

###############################################################################
# Colour helpers
###############################################################################
GREEN='\033[1;32m'; BLUE='\033[1;34m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; NC='\033[0m'
step()  { echo -e "\n${BLUE}▶ $*${NC}"; }
ok()    { echo -e "${GREEN}✔ $*${NC}"; }
warn()  { echo -e "${YELLOW}⚠ $*${NC}"; }
error() { echo -e "${RED}✖ $*${NC}"; exit 1; }

###############################################################################
# Preflight checks
###############################################################################
step "Preflight checks"

command -v gcloud   >/dev/null 2>&1 || error "gcloud CLI not found. Install: https://cloud.google.com/sdk/install"
command -v docker   >/dev/null 2>&1 || error "Docker not found."
command -v terraform >/dev/null 2>&1 || error "Terraform not found. Install: https://developer.hashicorp.com/terraform/install"

gcloud config set project "${PROJECT_ID}" --quiet
ok "GCP project set to: ${PROJECT_ID}"

###############################################################################
# Bootstrap: GCS state bucket + APIs
###############################################################################
bootstrap_infra() {
  step "Bootstrapping GCP project"

  echo "→ Enabling core APIs..."
  gcloud services enable \
    cloudresourcemanager.googleapis.com \
    iam.googleapis.com \
    artifactregistry.googleapis.com \
    storage.googleapis.com \
    --project="${PROJECT_ID}" --quiet

  STATE_BUCKET="${PROJECT_ID}-tfstate"
  if ! gsutil ls "gs://${STATE_BUCKET}" >/dev/null 2>&1; then
    echo "→ Creating Terraform state bucket: gs://${STATE_BUCKET}"
    gsutil mb -p "${PROJECT_ID}" -l "${REGION}" "gs://${STATE_BUCKET}"
    gsutil versioning set on "gs://${STATE_BUCKET}"
  else
    echo "→ State bucket already exists."
  fi

  echo "→ Configuring Docker auth for Artifact Registry..."
  gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

  ok "Bootstrap complete."
}

###############################################################################
# Terraform: init → plan → apply
###############################################################################
terraform_deploy() {
  step "Terraform — initialising"

  cd "${TF_DIR}"

  terraform init \
    -backend-config="bucket=${PROJECT_ID}-tfstate" \
    -backend-config="prefix=greenops-copilot/state" \
    -input=false \
    -upgrade \
    -reconfigure

  step "Terraform — planning"
  terraform plan \
    -var="project_id=${PROJECT_ID}" \
    -var="primary_region=${REGION}" \
    -var="image_tag=${IMAGE_TAG}" \
    -input=false \
    -out="/tmp/greenops-tfplan"

  step "Terraform — applying"
  terraform apply \
    -input=false \
    -auto-approve \
    "/tmp/greenops-tfplan"

  # Capture outputs
  ORCHESTRATOR_URL=$(terraform output -raw orchestrator_url 2>/dev/null || echo "")
  FRONTEND_URL=$(terraform output -raw frontend_url 2>/dev/null || echo "")

  ok "Terraform apply complete."

  cd - >/dev/null
}

###############################################################################
# Container builds
###############################################################################
build_images() {
  step "Building container images (tag: ${IMAGE_TAG})"

  docker build \
    -t "${REGISTRY}/orchestrator:${IMAGE_TAG}" \
    -t "${REGISTRY}/orchestrator:latest" \
    -f backend/Dockerfile backend/
  ok "Orchestrator image built."

  docker build \
    -t "${REGISTRY}/frontend:${IMAGE_TAG}" \
    -t "${REGISTRY}/frontend:latest" \
    -f frontend/Dockerfile frontend/
  ok "Frontend image built."

  docker build \
    -t "${REGISTRY}/executor:${IMAGE_TAG}" \
    -t "${REGISTRY}/executor:latest" \
    -f executor/Dockerfile executor/
  ok "Executor image built."
}

push_images() {
  step "Pushing images to Artifact Registry"

  for service in orchestrator frontend executor; do
    docker push "${REGISTRY}/${service}:${IMAGE_TAG}"
    docker push "${REGISTRY}/${service}:latest"
    ok "  Pushed: ${service}:${IMAGE_TAG}"
  done
}

###############################################################################
# Smoke test
###############################################################################
smoke_test() {
  step "Smoke testing deployed services"

  if [ -z "${ORCHESTRATOR_URL:-}" ]; then
    ORCHESTRATOR_URL=$(cd "${TF_DIR}" && terraform output -raw orchestrator_url 2>/dev/null || echo "")
  fi

  if [ -z "${ORCHESTRATOR_URL}" ]; then
    warn "Could not retrieve orchestrator URL. Skipping smoke test."
    return
  fi

  echo "→ Testing: ${ORCHESTRATOR_URL}/health"
  for i in $(seq 1 12); do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${ORCHESTRATOR_URL}/health" 2>/dev/null || echo "000")
    echo "  Attempt ${i}/12: HTTP ${STATUS}"
    if [ "${STATUS}" = "200" ]; then
      ok "Orchestrator is healthy."
      return
    fi
    sleep 5
  done

  warn "Smoke test did not pass within 60s. Service may still be starting."
}

###############################################################################
# Status summary
###############################################################################
print_status() {
  step "Deployment summary"

  ORCH_URL=$(gcloud run services describe greenops-orchestrator \
    --project="${PROJECT_ID}" --region="${REGION}" \
    --format="value(status.url)" 2>/dev/null || echo "not deployed")
  FE_URL=$(gcloud run services describe greenops-frontend \
    --project="${PROJECT_ID}" --region="${REGION}" \
    --format="value(status.url)" 2>/dev/null || echo "not deployed")

  echo ""
  echo -e "  ${GREEN}Orchestrator:${NC} ${ORCH_URL}"
  echo -e "  ${GREEN}Frontend:    ${NC} ${FE_URL}"
  echo -e "  ${GREEN}Registry:    ${NC} ${REGISTRY}"
  echo -e "  ${GREEN}Image tag:   ${NC} ${IMAGE_TAG}"
  echo ""
}

###############################################################################
# Destroy
###############################################################################
terraform_destroy() {
  warn "DESTROYING all GreenOps resources in project: ${PROJECT_ID}"
  read -p "Type 'yes' to confirm: " CONFIRM
  [ "${CONFIRM}" = "yes" ] || error "Aborted."

  cd "${TF_DIR}"
  terraform destroy \
    -var="project_id=${PROJECT_ID}" \
    -var="primary_region=${REGION}" \
    -var="image_tag=${IMAGE_TAG}" \
    -input=false \
    -auto-approve
  cd - >/dev/null
  ok "Destroy complete."
}

###############################################################################
# Entry point
###############################################################################
case "${MODE}" in
  full)
    bootstrap_infra
    build_images
    push_images
    terraform_deploy
    smoke_test
    print_status
    ok "GreenOps Copilot deployed. Visit the frontend URL above."
    ;;
  --infra-only)
    terraform_deploy
    print_status
    ;;
  --images-only)
    build_images
    push_images
    ok "Images pushed to ${REGISTRY}"
    ;;
  --destroy)
    terraform_destroy
    ;;
  *)
    echo "Usage: $0 [--infra-only | --images-only | --destroy]"
    exit 1
    ;;
esac
