# gcp-gce-server

Creates a Google Cloud Compute Engine (GCE) virtual machine and prepares it to
run an application, including its environment variables and secrets.

### Overview

This module provisions a GCE instance with a dedicated workload service account
and boots it with cloud-init. Through capabilities, the instance can attach
disks and contribute application configuration. Environment variables and
secrets are aggregated from the app and its capabilities, then delivered to the
workload at boot.

### Disk attachment

If you attach a disk to the instance (usually through a capability), this module
mounts it for you. The disk is mounted at `/mnt/<device-name>`, where
`device_name` is configured by the capability.

### Environment variables and secrets

The module aggregates environment variables and secrets from the application
configuration and its attached capabilities, then delivers them to the workload
at boot through cloud-init. Two manifests are written to the instance:

- `/etc/app/env.manifest` holds non-sensitive environment variables as
  `KEY=VALUE` entries.
- `/etc/app/secrets.manifest` holds secrets as `KEY=<secret_id>`. Only the
  Google Secret Manager identifier is stored here. Secret values never touch the
  boot disk or Terraform state.

At boot, `load-app-secrets.sh` reads both manifests and resolves each secret
from Secret Manager using the VM's own service account. It obtains an access
token from the metadata server and calls the Secret Manager REST API directly,
so it needs neither gcloud nor docker and works on any GCE image. The combined
result is written to a tmpfs (RAM only) mount at `/run/app-secrets/app.env`.

The loader is atomic and fail-closed. It assembles the file in a temporary file
on the tmpfs mount and publishes `app.env` only after every secret resolves. If
any secret cannot be fetched, the loader aborts and leaves no `app.env`, so the
application is never started with partial credentials. A workload typically
consumes the result with `--env-file /run/app-secrets/app.env`.

### Notes

- Secrets are delivered as environment variables in `app.env`. Secrets that must
  exist as files on disk, such as SSH host keys, are handled by the specific
  capability that requires them.
- Running a container is the responsibility of the capability. Use a
  docker-capable image such as Container-Optimized OS for workloads that run via
  `docker run`.
