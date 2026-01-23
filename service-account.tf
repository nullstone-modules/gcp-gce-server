resource "google_service_account" "app" {
  account_id   = local.resource_name
  display_name = "Service Account for Nullstone Server ${local.block_name}"
}

// This allows the app's GCP service account to create an oauth token for itself
// This is generally useful, but this enables a situation where code wants to generate GCS bucket object signed URLs
resource "google_service_account_iam_member" "app_generate_token_self" {
  service_account_id = google_service_account.app.id
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.app.email}"
}

// See https://cloud.google.com/kubernetes-engine/docs/tutorials/workload-identity-secrets
resource "google_secret_manager_secret_iam_member" "secrets_access" {
  for_each = local.all_secret_keys

  secret_id = local.all_secrets[each.value]
  project   = local.project_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.app.email}"
}
