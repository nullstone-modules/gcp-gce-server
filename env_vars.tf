// Environment Variables and Secrets
//
// Aggregates env vars and secrets from:
// - Standard / Google env (NULLSTONE_*, GOOGLE_*)
// - User input (var.env_vars, var.secrets)
// - Capability outputs (env, secrets)
//
// Secrets handling:
// 1. Create managed GSM secrets unless the value is {{ secret(<id>) }} (existing).
// 2. Grant the VM service account secretAccessor on each secret (see service-account.tf).
// 3. Expose secret IDs via secrets.manifest; load-app-secrets.sh resolves them at boot into tmpfs.

variable "env_vars" {
  type        = map(string)
  default     = {}
  description = <<EOF
The environment variables to inject into the service.
These are typically used to configure a service per environment.
It is dangerous to put sensitive information in this variable because they are not protected and could be unintentionally exposed.
EOF
}

variable "secrets" {
  type        = map(string)
  default     = {}
  sensitive   = true
  description = <<EOF
The sensitive environment variables to inject into the service.
These are typically used to configure a service per environment.
EOF
}

locals {
  cap_env_vars = {
    for item in local.capabilities.env : "${local.cap_env_prefixes[item.cap_tf_id]}${item.name}" => item.value
  }
  cap_secrets = {
    for item in local.capabilities.secrets : "${local.cap_env_prefixes[item.cap_tf_id]}${item.name}" => sensitive(item.value)
  }

  standard_env_vars = tomap({
    NULLSTONE_STACK         = data.ns_workspace.this.stack_name
    NULLSTONE_APP           = data.ns_workspace.this.block_name
    NULLSTONE_ENV           = data.ns_workspace.this.env_name
    NULLSTONE_VERSION       = data.ns_app_env.this.version
    NULLSTONE_COMMIT_SHA    = data.ns_app_env.this.commit_sha
    NULLSTONE_PUBLIC_HOSTS  = join(",", local.public_hosts)
    NULLSTONE_PRIVATE_HOSTS = join(",", local.private_hosts)
  })
  google_env_vars = tomap({
    GOOGLE_CLOUD_PROJECT         = local.project_id
    GOOGLE_CLOUD_PROJECT_NUMBER  = local.project_number
    GOOGLE_SERVICE_ACCOUNT_EMAIL = google_service_account.app.email
  })

  input_env_vars    = merge(local.standard_env_vars, local.google_env_vars, local.cap_env_vars, var.env_vars)
  input_secrets     = merge(local.cap_secrets, var.secrets)
  input_secret_keys = nonsensitive(concat(keys(local.cap_secrets), keys(var.secrets)))
}

data "ns_env_variables" "this" {
  input_env_variables = local.input_env_vars
  input_secrets       = local.input_secrets
}

// Detect {{ secret(<id>) }} refs (user + capability) so existing secrets get IAM
// only — they must not be re-created as managed secrets.
data "ns_env_variables" "existing" {
  input_env_variables = var.env_vars
  input_secrets       = local.input_secrets
}

data "ns_secret_keys" "this" {
  input_env_variables = var.env_vars
  input_secret_keys   = local.input_secret_keys
}

locals {
  // all_env_vars contains all environment variables excluding those detected as secrets
  // This is a map of name => value
  all_env_vars = data.ns_env_variables.this.env_variables

  // unmanaged_secret_keys are secrets that are not managed by this module
  // This is a list of string for all references where a user specified {{ secret(...) }}
  // The value of each item is the "..." inside secret()
  unmanaged_secret_keys = toset([for key, value in data.ns_env_variables.existing.secret_refs : key])
  // managed_secret_keys is a list of keys for secrets that this module manages
  // This excludes references to existing secrets {{ secret(...) }}
  managed_secret_keys = setsubtract(data.ns_secret_keys.this.secret_keys, local.unmanaged_secret_keys)
  all_secret_keys     = toset(concat(tolist(local.unmanaged_secret_keys), tolist(local.managed_secret_keys)))

  // unmanaged_secrets is a map of name => secret_ref
  unmanaged_secrets = data.ns_env_variables.existing.secret_refs
  // managed_secrets is a map of name => secret_ref
  managed_secrets = { for key in local.managed_secret_keys : key => google_secret_manager_secret.app_secret[key].secret_id }
  // managed_secret_values is a map of name => value
  managed_secret_values = data.ns_env_variables.this.secrets
  all_secrets           = merge(local.unmanaged_secrets, local.managed_secrets)
}
