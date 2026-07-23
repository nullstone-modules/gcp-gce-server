# gcp-gce-server

Provisions a Google Compute Engine VM with a dedicated workload service account
and cloud-init delivery of application environment variables and secrets.

## Disk attachment

Attached disks (usually via a capability) are mounted at `/mnt/<device-name>`.

## Environment variables and secrets

Aggregates env and secrets from the app configuration and attached capabilities,
then delivers them through cloud-init:

| Path | Contents |
|------|----------|
| `/etc/app/env.manifest` | Non-sensitive `KEY=VALUE` |
| `/etc/app/secrets.manifest` | `KEY=<gsm_secret_id>` (identifiers only) |
| `/usr/local/bin/load-app-secrets.sh` | Boot/runtime loader |

`load-app-secrets.sh` resolves each secret with the VM metadata access token and
the Secret Manager REST API (no gcloud, no docker), then writes
`/run/app-secrets/app.env` on tmpfs. The write is atomic and fail-closed.

Cloud-init runs the loader once at first boot. Because `/run/app-secrets` is
tmpfs, workloads (for example `gcp-gce-docker-app`) should re-invoke the loader
on every service start so `app.env` exists after reboot.

## Notes

- Secret **values** never appear in Terraform state, instance metadata, or the
  boot disk — only secret IDs.
- Secrets that must be files (SSH host keys) are handled by the capability that
  needs them.
- Use a docker-capable image such as Container-Optimized OS for `docker run`
  workloads.
