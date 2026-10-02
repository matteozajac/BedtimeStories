locals {
  region         = "europe-west1"
  worker_enabled = var.worker_image != null
  services = toset([
    "serviceusage.googleapis.com", "cloudresourcemanager.googleapis.com", "iam.googleapis.com",
    "firebase.googleapis.com", "firebasestorage.googleapis.com", "firebaseappcheck.googleapis.com",
    "identitytoolkit.googleapis.com", "firestore.googleapis.com", "storage.googleapis.com",
    "cloudkms.googleapis.com", "aiplatform.googleapis.com", "cloudtasks.googleapis.com",
    "run.googleapis.com", "cloudscheduler.googleapis.com", "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com", "artifactregistry.googleapis.com", "eventarc.googleapis.com",
    "pubsub.googleapis.com", "logging.googleapis.com", "iamcredentials.googleapis.com",
  ])
}
resource "google_project" "app" {
  project_id      = var.project_id
  name            = var.display_name
  billing_account = var.billing_account
  lifecycle { prevent_destroy = true }
}
resource "google_project_service" "apis" {
  for_each           = local.services
  project            = google_project.app.project_id
  service            = each.value
  disable_on_destroy = false
}
resource "google_firebase_project" "app" {
  provider   = google-beta
  project    = google_project.app.project_id
  depends_on = [google_project_service.apis]
}
resource "google_firestore_database" "app" {
  project                 = google_project.app.project_id
  name                    = "(default)"
  location_id             = local.region
  type                    = "FIRESTORE_NATIVE"
  delete_protection_state = "DELETE_PROTECTION_ENABLED"
  depends_on              = [google_firebase_project.app]
  lifecycle { prevent_destroy = true }
}
resource "google_storage_bucket" "private" {
  for_each                    = toset(["voices", "audio"])
  project                     = google_project.app.project_id
  name                        = "${var.project_id}-${each.key}"
  location                    = local.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false
  versioning { enabled = false }
  soft_delete_policy { retention_duration_seconds = 0 }
  depends_on = [google_project_service.apis]
  lifecycle { prevent_destroy = true }
}
resource "google_kms_key_ring" "voices" {
  project    = google_project.app.project_id
  name       = "bedtime-voices"
  location   = local.region
  depends_on = [google_project_service.apis]
}
resource "google_kms_crypto_key" "voices" {
  name            = "enrollment-envelopes"
  key_ring        = google_kms_key_ring.voices.id
  rotation_period = "7776000s"
  lifecycle { prevent_destroy = true }
}
resource "google_service_account" "app" {
  for_each     = toset(["voice-api", "voice-worker", "voice-queue", "voice-scheduler"])
  project      = google_project.app.project_id
  account_id   = each.value
  display_name = "BedtimeStories ${each.value}"
  depends_on   = [google_project_service.apis]
}
resource "google_artifact_registry_repository" "worker" {
  project       = google_project.app.project_id
  location      = local.region
  repository_id = "bedtime-voice"
  format        = "DOCKER"
  depends_on    = [google_project_service.apis]
}
resource "google_cloud_tasks_queue" "worker" {
  project  = google_project.app.project_id
  location = local.region
  name     = "bedtime-voice-worker"
  rate_limits {
    max_concurrent_dispatches = 2
    max_dispatches_per_second = 1
  }
  retry_config {
    max_attempts  = 30
    min_backoff   = "30s"
    max_backoff   = "300s"
    max_doublings = 4
    # Cloud Tasks stops only after BOTH limits are satisfied. A 1-second age
    # threshold expires before the first retry, so the 30-attempt cap governs.
    max_retry_duration = "1s"
  }
  stackdriver_logging_config { sampling_ratio = 0 }
  depends_on = [google_project_service.apis]
}
resource "google_cloud_run_v2_service" "worker" {
  count                = local.worker_enabled ? 1 : 0
  project              = google_project.app.project_id
  name                 = "bedtime-voice-worker"
  location             = local.region
  deletion_protection  = true
  invoker_iam_disabled = false
  ingress              = "INGRESS_TRAFFIC_ALL"
  template {
    service_account                  = google_service_account.app["voice-worker"].email
    timeout                          = "1800s"
    max_instance_request_concurrency = 1
    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }
    containers {
      image = var.worker_image
      resources { limits = { cpu = "2", memory = "2Gi" } }
      dynamic "env" {
        for_each = {
          GCLOUD_PROJECT = var.project_id
          VOICE_BUCKET   = google_storage_bucket.private["voices"].name
          OUTPUT_BUCKET  = google_storage_bucket.private["audio"].name
          KMS_KEY_NAME   = google_kms_crypto_key.voices.id
        }
        content {
          name  = env.key
          value = env.value
        }
      }
    }
  }
  depends_on = [google_project_service.apis, google_project_iam_member.worker_permissions]
  lifecycle {
    precondition {
      condition     = startswith(var.worker_image, "europe-west1-docker.pkg.dev/${var.project_id}/")
      error_message = "The worker image must belong to this dedicated project."
    }
  }
}
resource "google_cloud_run_v2_service_iam_binding" "private_invokers" {
  count    = local.worker_enabled ? 1 : 0
  project  = var.project_id
  location = local.region
  name     = google_cloud_run_v2_service.worker[0].name
  role     = "roles/run.invoker"
  members = [
    "serviceAccount:${google_service_account.app["voice-queue"].email}",
    "serviceAccount:${google_service_account.app["voice-scheduler"].email}",
  ]
}
resource "google_cloud_scheduler_job" "cleanup" {
  count            = local.worker_enabled ? 1 : 0
  project          = var.project_id
  region           = local.region
  name             = "bedtime-private-audio-cleanup"
  schedule         = "17 2 * * *"
  time_zone        = "UTC"
  attempt_deadline = "1800s"
  http_target {
    http_method = "POST"
    uri         = "${google_cloud_run_v2_service.worker[0].uri}/cleanup"
    oidc_token {
      service_account_email = google_service_account.app["voice-scheduler"].email
      audience              = google_cloud_run_v2_service.worker[0].uri
    }
  }
  depends_on = [google_cloud_run_v2_service_iam_binding.private_invokers]
}
