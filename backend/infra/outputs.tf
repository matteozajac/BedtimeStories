output "project_id" { value = var.project_id }
output "voice_bucket" { value = google_storage_bucket.private["voices"].name }
output "output_bucket" { value = google_storage_bucket.private["audio"].name }
output "kms_key_name" { value = google_kms_crypto_key.voices.id }
output "worker_url" { value = local.worker_enabled ? google_cloud_run_v2_service.worker[0].uri : null }
output "api_service_account" { value = google_service_account.app["voice-api"].email }
output "task_service_account" { value = google_service_account.app["voice-queue"].email }
output "functions_environment" {
  value = {
    ENABLE_CLOUD_NARRATION = "false"
    PROJECT_ID             = var.project_id
    API_SERVICE_ACCOUNT    = google_service_account.app["voice-api"].email
    VOICE_BUCKET           = google_storage_bucket.private["voices"].name
    OUTPUT_BUCKET          = google_storage_bucket.private["audio"].name
    KMS_KEY_NAME           = google_kms_crypto_key.voices.id
    TASK_LOCATION          = local.region
    TASK_QUEUE             = google_cloud_tasks_queue.worker.name
    TASK_SERVICE_ACCOUNT   = google_service_account.app["voice-queue"].email
    WORKER_URL             = local.worker_enabled ? google_cloud_run_v2_service.worker[0].uri : ""
  }
}
