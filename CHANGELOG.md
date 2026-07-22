# Changelog

### 0.1.0 (Unreleased)

- Initial release.
- Add environment variable and secret delivery through cloud-init.
  - Aggregate environment variables and secrets from the application and its
    capabilities.
  - Write `/etc/app/env.manifest` with non-sensitive `KEY=VALUE` entries.
  - Write `/etc/app/secrets.manifest` with `KEY=<secret_id>` entries
    (identifiers only, never secret values).
  - Add `load-app-secrets.sh`, a generic boot-time loader that resolves each
    secret from Google Secret Manager using the metadata access token and the
    REST API (no gcloud, no docker), then writes `/run/app-secrets/app.env` in
    tmpfs.
  - The loader is atomic and fail-closed. Secret values never touch the boot
    disk or Terraform state.
  - Add `cloud_init_stanzas` to the capability output contract so capabilities
    can contribute cloud-init to the server.
