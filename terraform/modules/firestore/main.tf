###############################################################################
# GreenOps Copilot — Firestore Module
###############################################################################

variable "project_id"     { type = string }
variable "primary_region" { type = string }

resource "google_firestore_database" "greenops" {
  project     = var.project_id
  name        = "(default)"
  location_id = var.primary_region
  type        = "FIRESTORE_NATIVE"

  delete_protection_state = "DELETE_PROTECTION_ENABLED"
  deletion_policy         = "DELETE"
}

# Index: sessions by user_id + updated_at (for active session lookup)
resource "google_firestore_index" "sessions_by_user" {
  project    = var.project_id
  database   = google_firestore_database.greenops.name
  collection = "sessions"

  fields {
    field_path = "user_id"
    order      = "ASCENDING"
  }
  fields {
    field_path = "updated_at"
    order      = "DESCENDING"
  }
}

# Index: alerts by region + threshold (for alert matching)
resource "google_firestore_index" "alerts_by_region" {
  project    = var.project_id
  database   = google_firestore_database.greenops.name
  collection = "green_alerts"

  fields {
    field_path = "region"
    order      = "ASCENDING"
  }
  fields {
    field_path = "threshold_gco2"
    order      = "ASCENDING"
  }
}

output "session_collection"    { value = "sessions" }
output "alert_collection"      { value = "green_alerts" }
output "firestore_database_id" { value = google_firestore_database.greenops.name }
