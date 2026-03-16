###############################################################################
# GreenOps Copilot — Makefile
# Single entrypoint for all local dev, build, and deployment operations.
#
# USAGE:
#   make setup           — first-time GCP project bootstrap
#   make deploy          — full production deploy (IaC + images + services)
#   make deploy-infra    — Terraform only (no image builds)
#   make deploy-images   — build & push images only
#   make destroy         — tear down all GCP resources
#   make logs            — tail orchestrator Cloud Run logs
#   make status          — print deployed URLs and service health
#   make secrets         — set API keys in Secret Manager
#
###############################################################################

# ── Config (override via environment or .env file) ───────────────────────────
-include .env

PROJECT_ID       ?= $(shell gcloud config get-value project 2>/dev/null)
REGION           ?= us-central1
IMAGE_TAG        ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo "latest")
TF_DIR           := terraform
REGISTRY         := $(REGION)-docker.pkg.dev/$(PROJECT_ID)/greenops-copilot
ENV_FILE         := .env

.PHONY: all setup deploy deploy-infra deploy-images destroy \
        logs status secrets tf-init tf-plan tf-apply tf-destroy \
        build-orchestrator build-frontend build-executor \
        push-orchestrator push-frontend push-executor \
        test lint clean help

# ── Default target ────────────────────────────────────────────────────────────
all: help

###############################################################################
# FIRST-TIME SETUP
###############################################################################

## setup: Bootstrap GCP project, enable APIs, create Terraform state bucket
setup: _require-project
	@echo "\n\033[1;32m▶ Setting up GCP project: $(PROJECT_ID)\033[0m\n"

	@echo "→ Authenticating with GCP..."
	gcloud auth application-default login

	@echo "→ Setting project..."
	gcloud config set project $(PROJECT_ID)

	@echo "→ Enabling bootstrap APIs..."
	gcloud services enable \
		cloudresourcemanager.googleapis.com \
		iam.googleapis.com \
		artifactregistry.googleapis.com \
		storage.googleapis.com

	@echo "→ Creating Terraform state bucket..."
	gsutil mb -p $(PROJECT_ID) -l $(REGION) gs://$(PROJECT_ID)-tfstate 2>/dev/null || \
		echo "  (bucket already exists, skipping)"
	gsutil versioning set on gs://$(PROJECT_ID)-tfstate

	@echo "→ Creating build artifacts bucket..."
	gsutil mb -p $(PROJECT_ID) -l $(REGION) gs://$(PROJECT_ID)-build-artifacts 2>/dev/null || \
		echo "  (bucket already exists, skipping)"

	@echo "→ Configuring Docker for Artifact Registry..."
	gcloud auth configure-docker $(REGION)-docker.pkg.dev --quiet

	@echo "\n\033[1;32m✔ Setup complete. Next: run 'make secrets' then 'make deploy'\033[0m\n"

###############################################################################
# SECRETS
###############################################################################

## secrets: Interactively set required API keys in Secret Manager
secrets: _require-project
	@echo "\n\033[1;33m▶ Setting secrets in Secret Manager\033[0m\n"

	@echo "→ Electricity Maps API key:"
	@read -s -p "  Paste key (input hidden): " EMAPS_KEY && echo "" && \
		printf "%s" "$$EMAPS_KEY" | \
		gcloud secrets versions add electricity-maps-api-key \
			--data-file=- --project=$(PROJECT_ID) 2>/dev/null || \
		(gcloud secrets create electricity-maps-api-key \
			--replication-policy=automatic --project=$(PROJECT_ID) && \
		printf "%s" "$$EMAPS_KEY" | \
		gcloud secrets versions add electricity-maps-api-key \
			--data-file=- --project=$(PROJECT_ID))

	@echo "→ Gemini API key:"
	@read -s -p "  Paste key (input hidden): " GEMINI_KEY && echo "" && \
		printf "%s" "$$GEMINI_KEY" | \
		gcloud secrets versions add gemini-api-key \
			--data-file=- --project=$(PROJECT_ID) 2>/dev/null || \
		(gcloud secrets create gemini-api-key \
			--replication-policy=automatic --project=$(PROJECT_ID) && \
		printf "%s" "$$GEMINI_KEY" | \
		gcloud secrets versions add gemini-api-key \
			--data-file=- --project=$(PROJECT_ID))

	@echo "\n\033[1;32m✔ Secrets stored in Secret Manager.\033[0m\n"

###############################################################################
# FULL DEPLOYMENT
###############################################################################

## deploy: Full deploy — IaC + build + push + apply (idempotent)
deploy: _require-project tf-init build-all push-all tf-apply status
	@echo "\n\033[1;32m✔ GreenOps Copilot deployed successfully.\033[0m\n"

## deploy-infra: Terraform only — update infrastructure without rebuilding images
deploy-infra: _require-project tf-init tf-apply

## deploy-images: Build and push images only — does not update infrastructure
deploy-images: _require-project build-all push-all

###############################################################################
# TERRAFORM
###############################################################################

## tf-init: Initialise Terraform with remote state backend
tf-init: _require-project
	@echo "\n\033[1;34m▶ Terraform init\033[0m"
	cd $(TF_DIR) && terraform init \
		-backend-config="bucket=$(PROJECT_ID)-tfstate" \
		-backend-config="prefix=greenops-copilot/state" \
		-input=false \
		-upgrade

## tf-plan: Show planned infrastructure changes
tf-plan: _require-project tf-init _write-tfvars
	@echo "\n\033[1;34m▶ Terraform plan\033[0m"
	cd $(TF_DIR) && terraform plan \
		-var="project_id=$(PROJECT_ID)" \
		-var="primary_region=$(REGION)" \
		-var="image_tag=$(IMAGE_TAG)" \
		-input=false

## tf-apply: Apply infrastructure changes
tf-apply: _require-project tf-init _write-tfvars
	@echo "\n\033[1;34m▶ Terraform apply\033[0m"
	cd $(TF_DIR) && terraform apply \
		-var="project_id=$(PROJECT_ID)" \
		-var="primary_region=$(REGION)" \
		-var="image_tag=$(IMAGE_TAG)" \
		-input=false \
		-auto-approve

## tf-destroy: DANGER — destroy all GCP resources managed by Terraform
tf-destroy: _require-project _confirm-destroy
	@echo "\n\033[1;31m▶ Terraform destroy\033[0m"
	cd $(TF_DIR) && terraform destroy \
		-var="project_id=$(PROJECT_ID)" \
		-var="primary_region=$(REGION)" \
		-var="image_tag=$(IMAGE_TAG)" \
		-input=false \
		-auto-approve

###############################################################################
# IMAGE BUILDS
###############################################################################

build-all: build-orchestrator build-frontend build-executor

## build-orchestrator: Build ADK Orchestrator Docker image
build-orchestrator:
	@echo "\n\033[1;34m▶ Building orchestrator image (tag: $(IMAGE_TAG))\033[0m"
	docker build \
		-t $(REGISTRY)/orchestrator:$(IMAGE_TAG) \
		-t $(REGISTRY)/orchestrator:latest \
		-f backend/Dockerfile \
		backend/

## build-frontend: Build React frontend Docker image
build-frontend:
	@echo "\n\033[1;34m▶ Building frontend image\033[0m"
	docker build \
		-t $(REGISTRY)/frontend:$(IMAGE_TAG) \
		-t $(REGISTRY)/frontend:latest \
		-f frontend/Dockerfile \
		frontend/

## build-executor: Build workload executor Docker image
build-executor:
	@echo "\n\033[1;34m▶ Building executor image\033[0m"
	docker build \
		-t $(REGISTRY)/executor:$(IMAGE_TAG) \
		-t $(REGISTRY)/executor:latest \
		-f executor/Dockerfile \
		executor/

###############################################################################
# IMAGE PUSHES
###############################################################################

push-all: push-orchestrator push-frontend push-executor

push-orchestrator:
	docker push $(REGISTRY)/orchestrator:$(IMAGE_TAG)
	docker push $(REGISTRY)/orchestrator:latest

push-frontend:
	docker push $(REGISTRY)/frontend:$(IMAGE_TAG)
	docker push $(REGISTRY)/frontend:latest

push-executor:
	docker push $(REGISTRY)/executor:$(IMAGE_TAG)
	docker push $(REGISTRY)/executor:latest

###############################################################################
# OPERATIONS
###############################################################################

## logs: Tail ADK Orchestrator Cloud Run logs
logs: _require-project
	gcloud run services logs tail greenops-orchestrator \
		--project=$(PROJECT_ID) \
		--region=$(REGION)

## status: Print deployed service URLs and health check results
status: _require-project
	@echo "\n\033[1;32m▶ GreenOps Copilot — deployment status\033[0m\n"

	@ORCH_URL=$$(gcloud run services describe greenops-orchestrator \
		--project=$(PROJECT_ID) --region=$(REGION) \
		--format="value(status.url)" 2>/dev/null) && \
	FE_URL=$$(gcloud run services describe greenops-frontend \
		--project=$(PROJECT_ID) --region=$(REGION) \
		--format="value(status.url)" 2>/dev/null) && \
	echo "  Orchestrator: $$ORCH_URL" && \
	echo "  Frontend:     $$FE_URL" && \
	echo "" && \
	echo "  Health check (orchestrator):" && \
	curl -s -o /dev/null -w "    HTTP %{http_code} in %{time_total}s\n" \
		"$$ORCH_URL/health" || echo "    Unreachable"

## destroy: Remove all Cloud Run services and Terraform-managed resources
destroy: tf-destroy
	@echo "\n\033[1;31m✔ All GreenOps resources destroyed.\033[0m\n"

###############################################################################
# DEVELOPMENT
###############################################################################

## test: Run unit tests for backend ADK tools
test:
	@echo "\n\033[1;34m▶ Running tests\033[0m"
	cd backend && python -m pytest tests/ -v --tb=short

## lint: Lint Python backend and Terraform
lint:
	@echo "\n\033[1;34m▶ Linting Python\033[0m"
	cd backend && python -m ruff check .
	@echo "\n\033[1;34m▶ Linting Terraform\033[0m"
	cd $(TF_DIR) && terraform fmt -check -recursive

## clean: Remove local build artifacts and Terraform cache
clean:
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -name "*.pyc" -delete 2>/dev/null || true
	rm -rf $(TF_DIR)/.terraform/providers
	rm -f $(TF_DIR)/.terraform.lock.hcl
	@echo "Clean complete."

###############################################################################
# HELPERS (internal targets, prefixed with _)
###############################################################################

_require-project:
	@if [ -z "$(PROJECT_ID)" ]; then \
		echo "\033[1;31mERROR: PROJECT_ID is not set.\033[0m"; \
		echo "Run: export PROJECT_ID=your-gcp-project-id"; \
		exit 1; \
	fi

_write-tfvars:
	@echo "project_id     = \"$(PROJECT_ID)\"" > $(TF_DIR)/auto.tfvars
	@echo "primary_region = \"$(REGION)\""     >> $(TF_DIR)/auto.tfvars
	@echo "image_tag      = \"$(IMAGE_TAG)\""  >> $(TF_DIR)/auto.tfvars

_confirm-destroy:
	@echo "\033[1;31mWARNING: This will destroy ALL GreenOps GCP resources.\033[0m"
	@read -p "Type 'yes' to confirm: " CONFIRM && \
		[ "$$CONFIRM" = "yes" ] || (echo "Aborted." && exit 1)

## help: List all available make targets
help:
	@echo ""
	@echo "\033[1mGreenOps Copilot — Available make targets\033[0m"
	@echo ""
	@grep -E '^## ' Makefile | sed 's/## /  /' | column -t -s ':'
	@echo ""
	@echo "\033[2mConfig: PROJECT_ID=$(PROJECT_ID)  REGION=$(REGION)  IMAGE_TAG=$(IMAGE_TAG)\033[0m"
	@echo ""
