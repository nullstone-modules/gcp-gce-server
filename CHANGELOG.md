# Changelog

### 0.1.0 (Unreleased)

- Deliver aggregated app and capability env/secrets through cloud-init.
  - Write `/app/env.manifest` (`KEY=VALUE`) and `/app/secrets.manifest`
    (`KEY=<secret_id>` only — never secret values).
  - Add `load-app-secrets.sh` at `/app/load-app-secrets.sh`: metadata token + Secret Manager REST (no gcloud,
    no docker); atomic, fail-closed write of `/run/app-secrets/app.env` on tmpfs.
  - Add `cloud_init_stanzas` to the capability output contract.
  - Treat capability `{{ secret(<id>) }}` refs as unmanaged existing secrets
    (`env_vars.tf`) — grant IAM, do not create new GSM secrets.
  - Include `load-app-secrets.sh` in `.nullstone/module.yml` for publish.
  - Inject `data_dir` and `secrets_mount` into `app_metadata` for capability coordination.
