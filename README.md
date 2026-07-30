# gcp-gce-server

Provisions a Google Compute Engine workload as a regional managed instance group
(size 1, all available zones) with a dedicated workload service account and
cloud-init delivery of application environment variables and secrets.

## Access

- Instances have **no public IP** (cheaper; safe under rolling replace).
- SSH: OS Login + IAP (`gcloud compute ssh <instance> --tunnel-through-iap`);
  firewall allows IAP IPv4 `35.235.240.0/20` and IPv6 `2600:2d00:1:7::/64`.
- Public app traffic: attach `gcp-gce-tcp-load-balancer`. The capability owns the
  target pool; this MIG joins it via the `load_balancers` capability output.

## Disk attachment

Attached disks (usually via a capability) are mounted at `/mnt/<device-name>`.
Persistent attached disks across MIG rolling replace are **not** designed yet;
treat as unsupported until a storage approach is agreed.

## Environment variables and secrets (server contract)

This module is the single owner of env vars and secrets. It aggregates them from
the app configuration and attached capabilities, then guarantees the following
locations on the instance for any workload (for example `gcp-gce-docker-app`):

| Path | Contents |
|------|----------|
| `/etc/nullstone/env.manifest` | Non-sensitive `KEY=VALUE` |
| `/etc/nullstone/secrets.manifest` | `KEY=<gsm_secret_id>` (identifiers only) |
| `/etc/nullstone/secret-files.manifest` | `<file name>=<gsm_secret_id>` from capabilities |
| `/etc/nullstone/load-app-secrets.sh` | Boot/runtime loader |
| `/etc/nullstone/mount-disks.sh` | Attached-disk mounter |
| `/run/app-secrets/app.env` | Resolved env + secrets (tmpfs) |
| `/run/app-secrets/<file name>` | Each capability file secret (tmpfs) |

Scaffold paths live under `/etc/nullstone` so they work on Container-Optimized OS
(read-only root; `/etc` is writable and executable). Cloud-init rewrites them
each boot. Resolved secrets remain on tmpfs under `/run/app-secrets`.

Built-in env `SECRETS_MOUNT_DIR` points at the secrets mount path (same value as
`app_metadata.secrets_mount`, default `/run/app-secrets`).

`load-app-secrets.sh` resolves each secret with the VM metadata access token and
the Secret Manager REST API (no gcloud, no docker), then writes `app.env` and any
secret files under `/run/app-secrets` on tmpfs. The `app.env` write is atomic and
fail-closed: if any secret fails to resolve, no `app.env` is produced.

Cloud-init runs the loader once at first boot. Because `/run/app-secrets` is
tmpfs, workloads should re-invoke the loader on every service start so the files
exist after reboot.

### Secret files (capability output)

File secrets are not a user variable. Attach a capability that exports
`secret_files` (for example `gcp-gce-mounted-ssh-keys`). The server reads
`local.capabilities.secret_files`, writes `/etc/nullstone/secret-files.manifest`,
and materializes each file on tmpfs.

## Notes

- Secret **values** never appear in Terraform state, instance metadata, or the
  boot disk — only secret IDs.
- Use a docker-capable image such as Container-Optimized OS for `docker run`
  workloads.
