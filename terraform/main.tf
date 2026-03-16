###############################################################################
# GreenOps Copilot — Terraform Root Configuration
# Gemini Live Agent Challenge — Live Agents Category
###############################################################################

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.30"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.30"
    }
  }

  # Uncomment after first apply to enable remote state
  backend "gcs" {
    bucket = ""project-7d668bc6-9d94-4bba-9c1"-tfstate"
    prefix = "greenops-copilot/state"
  }
}

###############################################################################
# Providers
###############################################################################

provider "google" {
  project = var.project_id
  region  = var.primary_region
}

provider "google-beta" {
  project = var.project_id
  region  = var.primary_region
}

###############################################################################
# Enable required GCP APIs
###############################################################################

locals {
  required_apis = [
    "run.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "bigquery.googleapis.com",
    "bigquerydatatransfer.googleapis.com",
    "firestore.googleapis.com",
    "cloudscheduler.googleapis.com",
    "pubsub.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "secretmanager.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "aiplatform.googleapis.com",
    "generativelanguage.googleapis.com",
    "carbon.googleapis.com",
  ]
}

resource "google_project_service" "apis" {
  for_each = toset(local.required_apis)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false

  timeouts {
    create = "10m"
    update = "10m"
  }
}

###############################################################################
# Artifact Registry — Docker image repository
###############################################################################

resource "google_artifact_registry_repository" "greenops" {
  provider      = google-beta
  project       = var.project_id
  location      = var.primary_region
  repository_id = "greenops-copilot"
  description   = "GreenOps Copilot container images"
  format        = "DOCKER"

  depends_on = [google_project_service.apis]
}

###############################################################################
# Secret Manager — external API keys
###############################################################################

resource "google_secret_manager_secret" "electricity_maps_api_key" {
  secret_id = "electricity-maps-api-key"
  project   = var.project_id
  replication { auto {} }
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "electricity_maps_placeholder" {
  secret      = google_secret_manager_secret.electricity_maps_api_key.id
  secret_data = "NOT_SET"
  lifecycle { ignore_changes = [secret_data] }
}

resource "google_secret_manager_secret" "watttime_username" {
  secret_id = "watttime-username"
  project   = var.project_id
  replication { auto {} }
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "watttime_username_placeholder" {
  secret      = google_secret_manager_secret.watttime_username.id
  secret_data = "NOT_SET"
  lifecycle { ignore_changes = [secret_data] }
}

resource "google_secret_manager_secret" "watttime_password" {
  secret_id = "watttime-password"
  project   = var.project_id
  replication { auto {} }
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "watttime_password_placeholder" {
  secret      = google_secret_manager_secret.watttime_password.id
  secret_data = "NOT_SET"
  lifecycle { ignore_changes = [secret_data] }
}

resource "google_secret_manager_secret" "carbon_provider" {
  secret_id = "carbon-provider"
  project   = var.project_id
  replication { auto {} }
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "carbon_provider_default" {
  secret      = google_secret_manager_secret.carbon_provider.id
  secret_data = "simulation"  # safe default — overridden by bootstrap.sh
  lifecycle { ignore_changes = [secret_data] }
}

resource "google_secret_manager_secret" "gemini_api_key" {
  secret_id = "gemini-api-key"
  project   = var.project_id

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "gemini_api_key_placeholder" {
  secret      = google_secret_manager_secret.gemini_api_key.id
  secret_data = "REPLACE_WITH_ACTUAL_KEY"

  lifecycle {
    ignore_changes = [secret_data]
  }
}

###############################################################################
# Module instantiations
###############################################################################

module "iam" {
  source     = "./modules/iam"
  project_id = var.project_id
  depends_on = [google_project_service.apis]
}

module "bigquery" {
  source         = "./modules/bigquery"
  project_id     = var.project_id
  primary_region = var.primary_region
  depends_on     = [google_project_service.apis]
}

module "firestore" {
  source         = "./modules/firestore"
  project_id     = var.project_id
  primary_region = var.primary_region
  depends_on     = [google_project_service.apis]
}

module "pubsub" {
  source     = "./modules/pubsub"
  project_id = var.project_id
  depends_on = [google_project_service.apis]
}

module "cloudrun" {
  source                  = "./modules/cloudrun"
  project_id              = var.project_id
  primary_region          = var.primary_region
  green_regions           = var.green_regions
  image_tag               = var.image_tag
  artifact_registry_repo  = google_artifact_registry_repository.greenops.name
  orchestrator_sa_email   = module.iam.orchestrator_sa_email
  electricity_maps_secret = google_secret_manager_secret.electricity_maps_api_key.id
  gemini_api_key_secret   = google_secret_manager_secret.gemini_api_key.id
  bigquery_dataset_id     = module.bigquery.carbon_dataset_id
  firestore_collection    = module.firestore.session_collection
  alert_topic_id          = module.pubsub.alert_topic_id
  depends_on              = [module.iam, module.bigquery, module.firestore, module.pubsub]
}

module "scheduler" {
  source               = "./modules/scheduler"
  project_id           = var.project_id
  primary_region       = var.primary_region
  orchestrator_url     = module.cloudrun.orchestrator_url
  orchestrator_sa_email = module.iam.orchestrator_sa_email
  depends_on           = [module.cloudrun]
}

module "monitoring" {
  source         = "./modules/monitoring"
  project_id     = var.project_id
  primary_region = var.primary_region
  alert_email    = var.alert_email
  depends_on     = [module.cloudrun, module.bigquery]
}
