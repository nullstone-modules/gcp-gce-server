resource "google_secret_manager_secret" "app_secret" {
  for_each = local.managed_secret_keys

  // Valid secret_id: [[a-zA-Z_0-9]+]
  secret_id = lower(replace("${local.resource_name}_${each.value}", "/[^a-zA-Z_0-9]/", "_"))
  labels    = local.labels

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "app_secret" {
  for_each = local.managed_secret_keys

  secret      = google_secret_manager_secret.app_secret[each.value].id
  secret_data = local.managed_secret_values[each.value]
}
