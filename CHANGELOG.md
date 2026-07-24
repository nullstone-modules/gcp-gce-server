# 0.1.0 (Unreleased)

* Accept capability `secret_files` output and materialize files on tmpfs via
  `/app/secret-files.manifest` and `load-app-secrets.sh`.
* Add built-in env `SECRETS_MOUNT_DIR` from `app_metadata.secrets_mount`.
