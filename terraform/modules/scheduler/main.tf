###############################################################################
# GreenOps Copilot — Cloud Scheduler Module
###############################################################################

variable "project_id"            { type = string }
variable "primary_region"        { type = string }
variable "orchestrator_url"      { type = string }
variable "orchestrator_sa_email" { type = string }

# Carbon intensity polling — every 5 minutes, all configured regions
resource "google_cloud_scheduler_job" "carbon_poll" {
  name        = "greenops-carbon-intensity-poll"
  description = "Poll Electricity Maps API and write gCO2/kWh to BigQuery every 5 minutes"
  schedule    = "*/5 * * * *"
  time_zone   = "UTC"
  region      = var.primary_region
  project     = var.project_id

  http_target {
    http_method = "POST"
    uri         = "${var.orchestrator_url}/internal/poll-carbon"
    body        = base64encode(jsonencode({ trigger = "scheduler", source = "cloud_scheduler" }))

    headers = {
      "Content-Type" = "application/json"
    }

    oidc_token {
      service_account_email = var.orchestrator_sa_email
      audience              = var.orchestrator_url
    }
  }

  retry_config {
    retry_count          = 3
    min_backoff_duration = "5s"
    max_backoff_duration = "60s"
    max_doublings        = 3
  }
}

# Daily carbon savings summary — sent to BigQuery at midnight UTC
resource "google_cloud_scheduler_job" "daily_summary" {
  name        = "greenops-daily-carbon-summary"
  description = "Aggregate daily carbon savings across all scheduled jobs"
  schedule    = "0 0 * * *"
  time_zone   = "UTC"
  region      = var.primary_region
  project     = var.project_id

  http_target {
    http_method = "POST"
    uri         = "${var.orchestrator_url}/internal/daily-summary"
    body        = base64encode(jsonencode({ trigger = "daily_summary" }))

    headers = {
      "Content-Type" = "application/json"
    }

    oidc_token {
      service_account_email = var.orchestrator_sa_email
      audience              = var.orchestrator_url
    }
  }

  retry_config {
    retry_count = 2
  }
}

# Green alert checker — evaluates active user alert thresholds every 10 minutes
resource "google_cloud_scheduler_job" "alert_checker" {
  name        = "greenops-green-alert-checker"
  description = "Check active user green window alerts against current carbon intensity"
  schedule    = "*/10 * * * *"
  time_zone   = "UTC"
  region      = var.primary_region
  project     = var.project_id

  http_target {
    http_method = "POST"
    uri         = "${var.orchestrator_url}/internal/check-alerts"
    body        = base64encode(jsonencode({ trigger = "alert_check" }))

    headers = {
      "Content-Type" = "application/json"
    }

    oidc_token {
      service_account_email = var.orchestrator_sa_email
      audience              = var.orchestrator_url
    }
  }

  retry_config {
    retry_count = 1
  }
}
