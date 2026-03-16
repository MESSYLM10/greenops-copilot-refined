###############################################################################
# GreenOps Copilot — Pub/Sub Module
# Topics and subscriptions for green window alerts and job events
###############################################################################

variable "project_id" { type = string }

###############################################################################
# Topic: green-window-alerts
# Published to when a region drops below a user's carbon threshold
###############################################################################

resource "google_pubsub_topic" "green_alerts" {
  name    = "greenops-green-window-alerts"
  project = var.project_id

  message_retention_duration = "600s" # 10 minutes — alerts are time-sensitive

  labels = { app = "greenops-copilot", type = "alerts" }
}

resource "google_pubsub_subscription" "green_alerts_orchestrator" {
  name    = "greenops-alerts-to-orchestrator"
  topic   = google_pubsub_topic.green_alerts.name
  project = var.project_id

  ack_deadline_seconds       = 20
  message_retention_duration = "600s"
  retain_acked_messages      = false

  expiration_policy { ttl = "" } # Never expire

  retry_policy {
    minimum_backoff = "5s"
    maximum_backoff = "60s"
  }

  labels = { app = "greenops-copilot" }
}

###############################################################################
# Topic: job-events
# Published to on Cloud Run Job state transitions (SCHEDULED, COMPLETE, FAILED)
###############################################################################

resource "google_pubsub_topic" "job_events" {
  name    = "greenops-job-events"
  project = var.project_id

  message_retention_duration = "86400s" # 24 hours

  labels = { app = "greenops-copilot", type = "job-events" }
}

resource "google_pubsub_subscription" "job_events_orchestrator" {
  name    = "greenops-job-events-to-orchestrator"
  topic   = google_pubsub_topic.job_events.name
  project = var.project_id

  ack_deadline_seconds       = 30
  message_retention_duration = "86400s"

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }

  labels = { app = "greenops-copilot" }
}

###############################################################################
# Dead letter topic — captures undeliverable messages
###############################################################################

resource "google_pubsub_topic" "dead_letter" {
  name    = "greenops-dead-letter"
  project = var.project_id

  labels = { app = "greenops-copilot", type = "dead-letter" }
}

###############################################################################
# Outputs
###############################################################################

output "alert_topic_id"     { value = google_pubsub_topic.green_alerts.id }
output "alert_topic_name"   { value = google_pubsub_topic.green_alerts.name }
output "job_events_topic_id" { value = google_pubsub_topic.job_events.id }
