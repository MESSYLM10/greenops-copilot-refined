###############################################################################
# GreenOps Copilot — Cloud Run Module
# ADK Orchestrator, React Frontend, and per-region Job executor
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
# ADK Orchestrator — FastAPI + ADK agent backend
###############################################################################

resource "google_cloud_run_v2_service" "orchestrator" {
  name     = "greenops-orchestrator"
  location = var.primary_region
  project  = var.project_id

  ingress = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = var.orchestrator_sa_email

    scaling {
      min_instance_count = 1   # Always-on — no cold start during Live demo
      max_instance_count = 10
    }

    containers {
      image = "${local.registry_base}/orchestrator:${var.image_tag}"

      resources {
        limits = {
          cpu    = "2"
          memory = "2Gi"
        }
        cpu_idle          = false  # Keep CPU allocated — needed for WebSocket streams
        startup_cpu_boost = true
      }

      ports {
        name           = "http1"
        container_port = 8080
      }

      # ── Application config ──
      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "PRIMARY_REGION"
        value = var.primary_region
      }
      env {
        name  = "GREEN_REGIONS"
        value = join(",", var.green_regions)
      }
      env {
        name  = "BIGQUERY_DATASET"
        value = var.bigquery_dataset_id
      }
      env {
        name  = "FIRESTORE_COLLECTION"
        value = var.firestore_collection
      }
      env {
        name  = "ALERT_TOPIC"
        value = var.alert_topic_id
      }
      env {
        name  = "GEMINI_MODEL"
        value = "gemini-2.0-flash-exp"
      }

      # ── Carbon provider (auto-detected from which secrets are set) ──
      env {
        name = "CARBON_PROVIDER"
        value_source {
          secret_key_ref {
            secret  = "carbon-provider"
            version = "latest"
          }
        }
      }

      # ── WattTime credentials (Tier 1) ──────────────────────────────
      env {
        name = "WATTTIME_USERNAME"
        value_source {
          secret_key_ref {
            secret  = "watttime-username"
            version = "latest"
          }
        }
      }
      env {
        name = "WATTTIME_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = "watttime-password"
            version = "latest"
          }
        }
      }

      # ── Electricity Maps (Tier 2) ───────────────────────────────────
      env {
        name = "ELECTRICITY_MAPS_API_KEY"
        value_source {
          secret_key_ref {
            secret  = var.electricity_maps_secret
            version = "latest"
          }
        }
      }
      env {
        name = "GEMINI_API_KEY"
        value_source {
          secret_key_ref {
            secret  = var.gemini_api_key_secret
            version = "latest"
          }
        }
      }

      startup_probe {
        http_get { path = "/health" }
        initial_delay_seconds = 5
        period_seconds        = 5
        failure_threshold     = 10
      }

      liveness_probe {
        http_get { path = "/health" }
        period_seconds    = 30
        failure_threshold = 3
      }
    }

    timeout = "3600s"  # 1 hour — support long Live API sessions
  }

  labels = {
    app         = "greenops-copilot"
    component   = "orchestrator"
    environment = "prod"
  }
}

# Allow unauthenticated invocations (the Live API frontend authenticates via session)
resource "google_cloud_run_v2_service_iam_member" "orchestrator_public" {
  project  = var.project_id
  location = var.primary_region
  name     = google_cloud_run_v2_service.orchestrator.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

###############################################################################
# React Frontend — static SPA served from Cloud Run
###############################################################################

resource "google_cloud_run_v2_service" "frontend" {
  name     = "greenops-frontend"
  location = var.primary_region
  project  = var.project_id

  ingress = "INGRESS_TRAFFIC_ALL"

  template {
    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      # Frontend image is updated by Cloud Build step "deploy-frontend" after
      # the real image is built with the correct orchestrator URL baked in.
      # On first terraform apply the placeholder ensures the service starts.
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

      env {
        name  = "ORCHESTRATOR_URL"
        value = google_cloud_run_v2_service.orchestrator.uri
      }
      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }
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
# Cloud Run Jobs — per-region workload executors
# One job template per green region; Cloud Scheduler triggers the right region
###############################################################################

resource "google_cloud_run_v2_job" "workload_executor" {
  for_each = toset(var.green_regions)

  name     = "greenops-executor-${replace(each.value, "/", "-")}"
  location = each.value
  project  = var.project_id

  template {
    template {
      service_account = var.orchestrator_sa_email

      containers {
        image = "${local.registry_base}/executor:${var.image_tag}"

        resources {
          limits = {
            cpu    = "4"
            memory = "8Gi"
          }
        }

        env {
          name  = "GCP_PROJECT_ID"
          value = var.project_id
        }
        env {
          name  = "EXECUTION_REGION"
          value = each.value
        }
        env {
          name  = "JOB_EVENTS_TOPIC"
          value = var.alert_topic_id
        }
      }

      max_retries = 2
      timeout     = "3600s"
    }
  }

  labels = {
    app    = "greenops-copilot"
    region = replace(each.value, "/", "-")
  }
}

###############################################################################
# Outputs
###############################################################################

output "orchestrator_url" { value = google_cloud_run_v2_service.orchestrator.uri }
output "frontend_url"     { value = google_cloud_run_v2_service.frontend.uri }
