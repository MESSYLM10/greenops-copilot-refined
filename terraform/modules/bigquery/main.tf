###############################################################################
# GreenOps Copilot — BigQuery Module
# Creates carbon intensity dataset, tables, and scheduled query
###############################################################################

variable "project_id"     { type = string }
variable "primary_region" { type = string }

###############################################################################
# Dataset
###############################################################################

resource "google_bigquery_dataset" "carbon" {
  dataset_id                  = "greenops_carbon"
  friendly_name               = "GreenOps Carbon Intensity"
  description                 = "Real-time and historical carbon intensity data for GreenOps Copilot"
  location                    = upper(var.primary_region) == "US-CENTRAL1" ? "US" : "EU"
  default_table_expiration_ms = null
  project                     = var.project_id

  labels = {
    app         = "greenops-copilot"
    environment = "prod"
    data_type   = "carbon"
  }
}

###############################################################################
# Table: carbon_intensity_log
# Written to by the get_carbon_intensity ADK tool on every API call
###############################################################################

resource "google_bigquery_table" "carbon_intensity_log" {
  dataset_id          = google_bigquery_dataset.carbon.dataset_id
  table_id            = "carbon_intensity_log"
  project             = var.project_id
  deletion_protection = false

  time_partitioning {
    type  = "DAY"
    field = "recorded_at"
  }

  clustering = ["region", "grid_zone"]

  schema = jsonencode([
    { name = "recorded_at",        type = "TIMESTAMP", mode = "REQUIRED", description = "When this reading was recorded" },
    { name = "region",             type = "STRING",    mode = "REQUIRED", description = "GCP region code, e.g. europe-west1" },
    { name = "grid_zone",          type = "STRING",    mode = "REQUIRED", description = "Electricity Maps grid zone code" },
    { name = "carbon_intensity",   type = "FLOAT64",   mode = "REQUIRED", description = "Carbon intensity in gCO2/kWh" },
    { name = "renewable_pct",      type = "FLOAT64",   mode = "NULLABLE", description = "Percentage of renewable energy (0-100)" },
    { name = "renewable_flag",     type = "BOOL",      mode = "REQUIRED", description = "True if region is above 70% renewable threshold" },
    { name = "fossil_fuel_pct",    type = "FLOAT64",   mode = "NULLABLE", description = "Percentage of fossil fuel generation" },
    { name = "data_source",        type = "STRING",    mode = "REQUIRED", description = "electricity_maps | gcp_carbon_footprint" },
    { name = "forecast_horizon_h", type = "INT64",     mode = "NULLABLE", description = "Hours ahead this is a forecast (null = realtime)" },
  ])

  labels = { app = "greenops-copilot" }
}

###############################################################################
# Table: scheduled_jobs
# Written to by schedule_workload ADK tool
###############################################################################

resource "google_bigquery_table" "scheduled_jobs" {
  dataset_id          = google_bigquery_dataset.carbon.dataset_id
  table_id            = "scheduled_jobs"
  project             = var.project_id
  deletion_protection = false

  time_partitioning {
    type  = "DAY"
    field = "scheduled_at"
  }

  schema = jsonencode([
    { name = "job_id",             type = "STRING",    mode = "REQUIRED", description = "Cloud Run Job ID" },
    { name = "scheduled_at",       type = "TIMESTAMP", mode = "REQUIRED", description = "When the schedule was created" },
    { name = "run_at",             type = "TIMESTAMP", mode = "REQUIRED", description = "Scheduled execution time" },
    { name = "target_region",      type = "STRING",    mode = "REQUIRED", description = "GCP region selected for execution" },
    { name = "workload_type",      type = "STRING",    mode = "NULLABLE", description = "User-provided workload description" },
    { name = "carbon_at_schedule", type = "FLOAT64",   mode = "NULLABLE", description = "gCO2/kWh at time of scheduling (current region)" },
    { name = "carbon_at_target",   type = "FLOAT64",   mode = "NULLABLE", description = "gCO2/kWh forecast for target region at run_at" },
    { name = "co2_saved_kg",       type = "FLOAT64",   mode = "NULLABLE", description = "Estimated CO2 savings vs. immediate execution (kg)" },
    { name = "co2_reduction_pct",  type = "FLOAT64",   mode = "NULLABLE", description = "Percentage reduction in carbon intensity" },
    { name = "status",             type = "STRING",    mode = "REQUIRED", description = "SCHEDULED | RUNNING | COMPLETE | FAILED" },
    { name = "user_session_id",    type = "STRING",    mode = "NULLABLE", description = "Firestore session ID for attribution" },
  ])

  labels = { app = "greenops-copilot" }
}

###############################################################################
# GCP Carbon Footprint export — links to billing account export
# Requires manual setup in GCP Console once; Terraform manages the dataset
###############################################################################

resource "google_bigquery_dataset" "gcp_carbon_footprint" {
  dataset_id    = "gcp_carbon_footprint_export"
  friendly_name = "GCP Carbon Footprint Export"
  description   = "GCP Carbon Footprint data exported from Cloud billing"
  location      = upper(var.primary_region) == "US-CENTRAL1" ? "US" : "EU"
  project       = var.project_id

  labels = { app = "greenops-copilot", data_type = "gcp-carbon" }
}

###############################################################################
# Outputs
###############################################################################

output "carbon_dataset_id"         { value = google_bigquery_dataset.carbon.dataset_id }
output "carbon_intensity_table_id" { value = google_bigquery_table.carbon_intensity_log.table_id }
output "scheduled_jobs_table_id"   { value = google_bigquery_table.scheduled_jobs.table_id }
output "gcp_footprint_dataset_id"  { value = google_bigquery_dataset.gcp_carbon_footprint.dataset_id }
