# gcp-gce-server

Provisions a Google Compute Engine VM with a dedicated workload service account
and cloud-init delivery of application environment variables and secrets.

## Disk attachment

Attached disks (usually via a capability) are mounted at `/mnt/<device-name>`.

## Environment variables and secrets (server contract)

This module is the single owner of env vars and secrets. It aggregates them from
the app configuration and attached capabilities, then guarantees the following
locations on the instance for any workload (for example `gcp-gce-docker-app`):

| Path | Contents |
|------|----------|
| `/app/env.manifest` | Non-sensitive `KEY=VALUE` |
| `/app/secrets.manifest` | `KEY=<gsm_secret_id>` (identifiers only) |
| `/app/secret-files.manifest` | `<file name>=<gsm_secret_id>` (identifiers only) |
| `/app/load-app-secrets.sh` | Boot/runtime loader |
| `/run/app-secrets/app.env` | Resolved env + secrets (tmpfs) |
| `/run/app-secrets/<file name>` | Each file-materialized secret (tmpfs) |

`load-app-secrets.sh` resolves each secret with the VM metadata access token and
the Secret Manager REST API (no gcloud, no docker), then writes `app.env` and any
secret files under `/run/app-secrets` on tmpfs. The `app.env` write is atomic and
fail-closed: if any secret fails to resolve, no `app.env` is produced.

Cloud-init runs the loader once at first boot. Because `/run/app-secrets` is
tmpfs, workloads should re-invoke the loader on every service start so the files
exist after reboot.

### Secret files (e.g. SSH host keys)

Use `var.secret_files` (a map of file name => Secret Manager secret id) for
secrets that must be files rather than env vars. The server fetches each at boot,
writes it to `/run/app-secrets/<file name>`, and grants the VM service account
`secretAccessor` on it. Workloads read these files from the read-only secrets
mount — the capability needs no IAM of its own.

## Notes

- Secret **values** never appear in Terraform state, instance metadata, or the
  boot disk — only secret IDs.
- Use a docker-capable image such as Container-Optimized OS for `docker run`
  workloads.
