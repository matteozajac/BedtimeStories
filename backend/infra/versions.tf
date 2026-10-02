terraform {
  required_version = ">= 1.9.0, < 2.0.0"
  required_providers {
    google      = { source = "hashicorp/google", version = "8.2.0" }
    google-beta = { source = "hashicorp/google-beta", version = "8.2.0" }
  }
}
provider "google" {
  project = var.project_id
  region  = "europe-west1"
}
provider "google-beta" {
  project = var.project_id
  region  = "europe-west1"
}
