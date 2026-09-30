resource "google_secret_manager_secret" "app_secret" {
  for_each = data.ns_env_layout.this.managed_secret_keys

  // Valid secret_id: [[a-zA-Z_0-9]+]
  secret_id = lower(replace("${local.resource_name}_${each.value}", "/[^a-zA-Z_0-9]/", "_"))
  labels    = local.labels

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "app_secret" {
  for_each = data.ns_env_layout.this.managed_secret_keys

  secret      = google_secret_manager_secret.app_secret[each.value].id
  secret_data = data.ns_env_values.this.secrets[each.value]
}

locals {
  // all_secrets is a map of name => secret_ref in GCP secrets manager
  // This is keyed from `ns_env_layout` so that the keys are known at plan time
  all_secrets = merge(
    { for key in data.ns_env_layout.this.unmanaged_secret_keys : key => data.ns_env_values.this.unmanaged_secret_refs[key] },
    { for key, secret in google_secret_manager_secret.app_secret : key => secret.secret_id },
  )
}
