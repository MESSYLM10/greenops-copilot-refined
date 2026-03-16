###############################################################################
# GreenOps Copilot — Cloud Monitoring Module
# Custom metrics, alerting policies, and uptime checks
###############################################################################

variable "project_id"     { type = string }
variable "primary_region" { type = string }
variable "alert_email"    { type = string }

###############################################################################
# Custom metric descriptors
###############################################################################

resource "google_monitoring_metric_descriptor" "co2_saved_kg" {
  project      = var.project_id
  description  = "Cumulative CO2 saved (kg) by scheduling workloads to green windows"
  display_name = "GreenOps: CO2 Saved (kg)"
  type         = "custom.googleapis.com/greenops/co2_saved_kg"
  metric_kind  = "CUMULATIVE"
  value_type   = "DOUBLE"
  unit         = "kg"

  labels {
    key         = "region"
    value_type  = "STRING"
    description = "GCP region where the job was executed"
  }
}

resource "google_monitoring_metric_descriptor" "carbon_intensity" {
  project      = var.project_id
  description  = "Current carbon intensity (gCO2/kWh) by GCP region"
  display_name = "GreenOps: Carbon Intensity (gCO2/kWh)"
  type         = "custom.googleapis.com/greenops/carbon_intensity_gco2_kwh"
  metric_kind  = "GAUGE"
  value_type   = "DOUBLE"
  unit         = "g{CO2}/kWh"

  labels {
    key         = "region"
    value_type  = "STRING"
    description = "GCP region"
  }
  labels {
    key         = "renewable_flag"
    value_type  = "BOOL"
    description = "Whether region is above 70% renewable threshold"
  }
}

resource "google_monitoring_metric_descriptor" "jobs_scheduled" {
  project      = var.project_id
  description  = "Number of workload jobs scheduled to green windows"
  display_name = "GreenOps: Jobs Scheduled"
  type         = "custom.googleapis.com/greenops/jobs_scheduled_total"
  metric_kind  = "CUMULATIVE"
  value_type   = "INT64"

  labels {
    key         = "target_region"
    value_type  = "STRING"
    description = "GCP region where job was scheduled"
  }
}

###############################################################################
# Uptime check — orchestrator health endpoint
###############################################################################

resource "google_monitoring_uptime_check_config" "orchestrator_health" {
  project      = var.project_id
  display_name = "GreenOps Orchestrator Health"
  timeout      = "10s"
  period       = "60s"

  http_check {
    path         = "/health"
    port         = "443"
    use_ssl      = true
    validate_ssl = true
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = "placeholder-update-after-deploy.run.app" # Updated via deploy script
    }
  }
}

###############################################################################
# Alert policy — orchestrator down
###############################################################################

resource "google_monitoring_notification_channel" "email" {
  count        = var.alert_email != "" ? 1 : 0
  project      = var.project_id
  display_name = "GreenOps Email Alerts"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }
}

resource "google_monitoring_alert_policy" "orchestrator_down" {
  project      = var.project_id
  display_name = "GreenOps Orchestrator Down"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Orchestrator uptime check failing"
    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\""
      comparison      = "COMPARISON_LT"
      threshold_value = 1
      duration        = "120s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_TRUE"
      }
    }
  }

  notification_channels = var.alert_email != "" ? [google_monitoring_notification_channel.email[0].name] : []

  alert_strategy {
    auto_close = "1800s"
  }
}

resource "google_monitoring_alert_policy" "high_carbon_intensity" {
  project      = var.project_id
  display_name = "GreenOps: All regions high carbon intensity"
  combiner     = "AND"
  enabled      = true

  conditions {
    display_name = "Carbon intensity above 400 gCO2/kWh across regions"
    condition_threshold {
      filter          = "metric.type=\"custom.googleapis.com/greenops/carbon_intensity_gco2_kwh\""
      comparison      = "COMPARISON_GT"
      threshold_value = 400
      duration        = "300s"
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_MEAN"
        cross_series_reducer = "REDUCE_MIN" # Fires only if ALL regions are above threshold
      }
    }
  }

  notification_channels = var.alert_email != "" ? [google_monitoring_notification_channel.email[0].name] : []
}
