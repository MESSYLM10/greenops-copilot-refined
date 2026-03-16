###############################################################################
# GreenOps Copilot — Cloud Run Module
###############################################################################

variable "project_id"              { type = string }
variable "primary_region"          { type = string }
variable "green_regions"           { type = list(string) }
variable "image_tag"               { type = string }
variable "artifact_registry_repo"  { type = string }
variable "orchestrator_sa_email"   { type = string }
variable "electricity_maps_secret" { type = string }
variable "gemini_api_key_secret"   { type = string }
variable "bigquery_dataset_id"     { type = string }
variable "firestore_collection"    { type = string }
variable "alert_topic_id"          { type = string }

locals {
  registry_base = "${var.primary_region}-docker.pkg.dev/${var.project_id}/${var.artifact_registry_repo}"
}

###############################################################################
# ADK Orchestrator
###############################################################################

resource "google_cloud_run_v2_service" "orchestrator" {
  name     = "greenops-orchestrator"
  location = var.primary_region
  project  = var.project_id
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = var.orchestrator_sa_email

    scaling {
      min_instance_count = 1
      max_instance_count = 10
    }

    containers {
      image = "${local.registry_base}/orchestrator:${var.image_tag}"

      resources {
        limits = {
          cpu    = "2"
          memory = "2Gi"
        }
        cpu_idle          = false
        startup_cpu_boost = true
      }

      ports {
        name           = "http1"
        container_port = 8080
      }

      env { name = "GCP_PROJECT_ID"       value = var.project_id }
      env { name = "PRIMARY_REGION"        value = var.primary_region }
      env { name = "GREEN_REGIONS"         value = join(",", var.green_regions) }
      env { name = "BIGQUERY_DATASET"      value = var.bigquery_dataset_id }
      env { name = "FIRESTORE_COLLECTION"  value = var.firestore_collection }
      env { name = "ALERT_TOPIC"           value = var.alert_topic_id }
      env { name = "GEMINI_MODEL"          value = "gemini-2.0-flash-exp" }
      env { name = "CARBON_PROVIDER"       value = "simulation" }
      env { name = "WATTTIME_USERNAME"     value = "" }
      env { name = "WATTTIME_PASSWORD"     value = "" }
      env { name = "ELECTRICITY_MAPS_API_KEY" value = "" }

      env {
        name = "GEMINI_API_KEY"
        value_source {
          secret_key_ref {
            secret  = "gemini-api-key"
            version = "latest"
          }
        }
      }

      startup_probe {
        http_get { path = "/health" }
        initial_delay_seconds = 10
        period_seconds        = 10
        failure_threshold     = 30
        timeout_seconds       = 5
      }

      liveness_probe {
        http_get { path = "/health" }
        period_seconds    = 30
        failure_threshold = 3
        timeout_seconds   = 5
      }
    }

    timeout = "3600s"
  }

  labels = {
    app       = "greenops-copilot"
    component = "orchestrator"
  }
}

resource "google_cloud_run_v2_service_iam_member" "orchestrator_public" {
  project  = var.project_id
  location = var.primary_region
  name     = google_cloud_run_v2_service.orchestrator.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

###############################################################################
# React Frontend
###############################################################################

resource "google_cloud_run_v2_service" "frontend" {
  name     = "greenops-frontend"
  location = var.primary_region
  project  = var.project_id
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      image = "${local.registry_base}/frontend:${var.image_tag}"

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle = true
      }

      ports {
        name           = "http1"
        container_port = 3000
      }

      env { name = "ORCHESTRATOR_URL" value = google_cloud_run_v2_service.orchestrator.uri }
      env { name = "GCP_PROJECT_ID"   value = var.project_id }
    }
  }

  labels = {
    app       = "greenops-copilot"
    component = "frontend"
  }

  depends_on = [google_cloud_run_v2_service.orchestrator]
}

resource "google_cloud_run_v2_service_iam_member" "frontend_public" {
  project  = var.project_id
  location = var.primary_region
  name     = google_cloud_run_v2_service.frontend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

###############################################################################
# Cloud Run Job — primary region only (quota limit on free tier)
###############################################################################

resource "google_cloud_run_v2_job" "workload_executor" {
  name     = "greenops-executor"
  location = var.primary_region
  project  = var.project_id

  template {
    template {
      service_account = var.orchestrator_sa_email

      containers {
        image = "${local.registry_base}/executor:${var.image_tag}"

        resources {
          limits = {
            cpu    = "2"
            memory = "4Gi"
          }
        }

        env { name = "GCP_PROJECT_ID"    value = var.project_id }
        env { name = "EXECUTION_REGION"  value = var.primary_region }
        env { name = "JOB_EVENTS_TOPIC"  value = var.alert_topic_id }
      }

      max_retries = 2
      timeout     = "3600s"
    }
  }

  labels = {
    app = "greenops-copilot"
  }
}

###############################################################################
# Outputs
###############################################################################

output "orchestrator_url" { value = google_cloud_run_v2_service.orchestrator.uri }
output "frontend_url"     { value = google_cloud_run_v2_service.frontend.uri }
