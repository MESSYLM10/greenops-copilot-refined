###############################################################################
# GreenOps Copilot — Terraform Variables
###############################################################################

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "primary_region" {
  description = "Primary GCP region for all managed services"
  type        = string
  default     = "us-central1"
}

variable "green_regions" {
  description = "GCP regions to consider for green workload scheduling (ordered by typical carbon intensity)"
  type        = list(string)
  default = [
    "europe-west1",   # Belgium  — high wind/solar
    "europe-north1",  # Finland  — near 100% renewable
    "us-west1",       # Oregon   — hydro-heavy
    "europe-west4",   # Netherlands
    "us-central1",    # Iowa     — growing wind
    "asia-east1",     # Taiwan
  ]
}

variable "image_tag" {
  description = "Container image tag to deploy (set by CI pipeline)"
  type        = string
  default     = "latest"
}

variable "alert_email" {
  description = "Email address for Cloud Monitoring alerts"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Deployment environment: dev | staging | prod"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}
