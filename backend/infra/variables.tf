variable "project_id" {
  type = string
  validation {
    condition     = can(regex("^bedtime-stories-(staging|prod)-[a-z0-9-]+$", var.project_id))
    error_message = "Use a dedicated BedtimeStories staging or production project."
  }
}
variable "display_name" { type = string }
variable "billing_account" {
  type = string
  validation {
    condition     = can(regex("^[A-F0-9]{6}-[A-F0-9]{6}-[A-F0-9]{6}$", var.billing_account))
    error_message = "Supply an independently verified billing account identifier."
  }
}
variable "worker_image" {
  type        = string
  default     = null
  description = "Set only after building/pushing the worker in this project's Artifact Registry. Null provisions foundation only."
  validation {
    condition     = var.worker_image == null || can(regex("^europe-west1-docker[.]pkg[.]dev/.+/bedtime-voice/worker@sha256:[a-f0-9]{64}$", var.worker_image))
    error_message = "Use the worker image's immutable SHA256 digest in the project's europe-west1 repository."
  }
}
