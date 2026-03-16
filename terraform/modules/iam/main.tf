###############################################################################
# GreenOps Copilot — IAM Module
# Creates service accounts and grants least-privilege roles
###############################################################################

variable "project_id" { type = string }

###############################################################################
# Service accounts
###############################################################################

resource "google_service_account" "orchestrator" {
  account_id   = "greenops-orchestrator"
  display_name = "GreenOps ADK Orchestrator"
  description  = "Service account for the ADK Orchestrator Cloud Run service"
  project      = var.project_id
}

resource "google_service_account" "frontend" {
  account_id   = "greenops-frontend"
  display_name = "GreenOps React Frontend"
  description  = "Service account for the React frontend Cloud Run service"
  project      = var.project_id
}

resource "google_service_account" "cloudbuild" {
  account_id   = "greenops-cloudbuild"
  display_name = "GreenOps Cloud Build"
  description  = "Service account for Cloud Build CI/CD pipeline"
  project      = var.project_id
}

###############################################################################
# Orchestrator SA roles
###############################################################################

locals {
  orchestrator_roles = [
    "roles/bigquery.dataViewer",
    "roles/bigquery.jobUser",
    "roles/datastore.user",           # Firestore
    "roles/pubsub.publisher",
    "roles/pubsub.subscriber",
    "roles/cloudscheduler.jobRunner",
    "roles/run.invoker",              # Call other Cloud Run services
    "roles/secretmanager.secretAccessor",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter",
  ]
}

resource "google_project_iam_member" "orchestrator_roles" {
  for_each = toset(local.orchestrator_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.orchestrator.email}"
}

###############################################################################
# Cloud Build SA roles
###############################################################################

locals {
  cloudbuild_roles = [
    "roles/run.admin",
    "roles/artifactregistry.writer",
    "roles/iam.serviceAccountUser",
    "roles/secretmanager.secretAccessor",
    "roles/logging.logWriter",
  ]
}

resource "google_project_iam_member" "cloudbuild_roles" {
  for_each = toset(local.cloudbuild_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

###############################################################################
# Outputs
###############################################################################

output "orchestrator_sa_email" {
  value = google_service_account.orchestrator.email
}

output "frontend_sa_email" {
  value = google_service_account.frontend.email
}

output "cloudbuild_sa_email" {
  value = google_service_account.cloudbuild.email
}
