###############################################################################
# GreenOps Copilot — Terraform Outputs
###############################################################################

output "orchestrator_url" {
  description = "ADK Orchestrator Cloud Run service URL"
  value       = module.cloudrun.orchestrator_url
}

output "frontend_url" {
  description = "React frontend Cloud Run service URL"
  value       = module.cloudrun.frontend_url
}

output "artifact_registry_repo" {
  description = "Artifact Registry repository URI"
  value       = "${var.primary_region}-docker.pkg.dev/${var.project_id}/greenops-copilot"
}

output "carbon_bigquery_dataset" {
  description = "BigQuery dataset for carbon intensity data"
  value       = module.bigquery.carbon_dataset_id
}

output "alert_pubsub_topic" {
  description = "Pub/Sub topic for green window alerts"
  value       = module.pubsub.alert_topic_id
}

output "orchestrator_service_account" {
  description = "Service account email used by the ADK Orchestrator"
  value       = module.iam.orchestrator_sa_email
}
