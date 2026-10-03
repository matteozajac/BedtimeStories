resource "google_project_iam_custom_role" "auth_worker" {
  project     = var.project_id
  role_id     = "bedtimeVoiceAuthDeletion"
  title       = "Bedtime voice account deletion"
  permissions = ["firebaseauth.users.get", "firebaseauth.users.update", "firebaseauth.users.delete"]
  depends_on  = [google_project_service.apis]
}
resource "google_project_iam_custom_role" "auth_api" {
  project     = var.project_id
  role_id     = "bedtimeVoiceAuthVerification"
  title       = "Bedtime voice revoked-user verification"
  permissions = ["firebaseauth.users.get"]
  depends_on  = [google_project_service.apis]
}
resource "google_project_iam_member" "worker_permissions" {
  for_each = {
    datastore = "roles/datastore.user"
    usage     = "roles/serviceusage.serviceUsageConsumer"
    gemini    = "roles/aiplatform.user"
    auth      = google_project_iam_custom_role.auth_worker.name
  }
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.app["voice-worker"].email}"
}
resource "google_project_iam_member" "api_permissions" {
  for_each = {
    datastore = "roles/datastore.user"
    usage     = "roles/serviceusage.serviceUsageConsumer"
    appcheck  = "roles/firebaseappcheck.tokenVerifier"
    auth      = google_project_iam_custom_role.auth_api.name
  }
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.app["voice-api"].email}"
}
resource "google_storage_bucket_iam_member" "worker_objects" {
  for_each = toset(["voices", "audio"])
  bucket   = google_storage_bucket.private[each.key].name
  role     = "roles/storage.objectUser"
  member   = "serviceAccount:${google_service_account.app["voice-worker"].email}"
}
resource "google_storage_bucket_iam_member" "api_recordings" {
  bucket = google_storage_bucket.private["voices"].name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.app["voice-api"].email}"
}
resource "google_kms_crypto_key_iam_member" "worker" {
  crypto_key_id = google_kms_crypto_key.voices.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.app["voice-worker"].email}"
}
resource "google_kms_crypto_key_iam_member" "api" {
  crypto_key_id = google_kms_crypto_key.voices.id
  role          = "roles/cloudkms.cryptoKeyEncrypter"
  member        = "serviceAccount:${google_service_account.app["voice-api"].email}"
}
resource "google_cloud_tasks_queue_iam_member" "enqueue" {
  project  = var.project_id
  location = local.region
  name     = google_cloud_tasks_queue.worker.name
  role     = "roles/cloudtasks.enqueuer"
  member   = "serviceAccount:${google_service_account.app["voice-api"].email}"
}
resource "google_service_account_iam_member" "api_queue_identity" {
  service_account_id = google_service_account.app["voice-queue"].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.app["voice-api"].email}"
}
resource "google_project_service_identity" "task_agent" {
  provider   = google-beta
  project    = var.project_id
  service    = "cloudtasks.googleapis.com"
  depends_on = [google_project_service.apis]
}
resource "google_project_service_identity" "scheduler_agent" {
  provider   = google-beta
  project    = var.project_id
  service    = "cloudscheduler.googleapis.com"
  depends_on = [google_project_service.apis]
}
resource "google_service_account_iam_member" "task_oidc" {
  service_account_id = google_service_account.app["voice-queue"].name
  role               = "roles/iam.serviceAccountOpenIdTokenCreator"
  member             = "serviceAccount:${google_project_service_identity.task_agent.email}"
}
resource "google_service_account_iam_member" "scheduler_oidc" {
  service_account_id = google_service_account.app["voice-scheduler"].name
  role               = "roles/iam.serviceAccountOpenIdTokenCreator"
  member             = "serviceAccount:${google_project_service_identity.scheduler_agent.email}"
}

# Storage rules consult account/job documents to authorize audio downloads.
# Only Google's Storage service agent receives the documented read-only role.
resource "google_project_service_identity" "storage_agent" {
  provider   = google-beta
  project    = var.project_id
  service    = "firebasestorage.googleapis.com"
  depends_on = [google_project_service.apis]
}
resource "google_project_iam_member" "storage_rule_documents" {
  project = var.project_id
  role    = "roles/firebaserules.firestoreServiceAgent"
  member  = "serviceAccount:${google_project_service_identity.storage_agent.email}"
}
