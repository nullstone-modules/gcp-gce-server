data "ns_app_env" "this" {
  stack_id = data.ns_workspace.this.stack_id
  app_id   = data.ns_workspace.this.block_id
  env_id   = data.ns_workspace.this.env_id
}

locals {
  app_version = data.ns_app_env.this.version
}

locals {
  data_dir          = "/var/lib/app"
  secrets_mount_dir = "/run/app-secrets"

  app_metadata = tomap({
    // Inject app metadata into capabilities here (e.g. service_account_email)
    service_account_id    = google_service_account.app.id
    service_account_email = google_service_account.app.email
    data_dir              = local.data_dir
    secrets_mount         = local.secrets_mount_dir
    // Network identity for ingress capabilities (no MIG resource refs).
    network       = local.vpc_name
    region        = local.region
    instance_tags = join(",", local.instance_tags)
  })
}
