# gcp-gce-server

Regional managed instance group (MIG) for a GCE workload: target size 1, all
available zones, workload service account, and cloud-init delivery of
environment variables and secrets.

Use a Docker-capable image (Container-Optimized OS recommended) when running
containers on the instance.

## Networking

| Item | Value |
|------|-------|
| Subnet | Private subnet from the connected `gcp-network` |
| VM public IP | None |
| Egress | Cloud NAT and Private Google Access |
| SSH | IAP / OS Login |

Workload VMs use the private subnet. The public subnet is for ingress devices
(NAT, load balancers).

### SSH

```bash
gcloud compute ssh <instance> --project=<project> --zone=<zone> --tunnel-through-iap
```

IAP firewall sources: IPv4 `35.235.240.0/20` and IPv6 `2600:2d00:1:7::/64`
(separate rules; GCP rejects mixed `source_ranges`).

## Secrets contract

| Path | Contents |
|------|----------|
| `/etc/nullstone/env.manifest` | Non-sensitive `KEY=VALUE` |
| `/etc/nullstone/secrets.manifest` | `KEY=<gsm_secret_id>` |
| `/etc/nullstone/secret-files.manifest` | `<file>=<gsm_secret_id>` from capabilities |
| `/etc/nullstone/load-app-secrets.sh` | Loader |
| `/run/app-secrets/app.env` | Resolved env and secrets (tmpfs) |
| `/run/app-secrets/<file>` | Capability secret files (tmpfs) |

Scaffold is under `/etc/nullstone` for COS. Resolved secrets stay on tmpfs.
`SECRETS_MOUNT_DIR` matches `app_metadata.secrets_mount` (default
`/run/app-secrets`).

`load-app-secrets.sh` uses the metadata access token and Secret Manager REST
(no gcloud, no docker). Fail-closed: no `app.env` if any secret fails. Re-run
the loader on every service start because tmpfs clears on reboot.

File secrets come from capability `secret_files`, not a user variable.
Bind-mount container paths from `/run/app-secrets/...` only.

## Upgrades

MIG policy: surge with `max_unavailable_fixed = 0`. Template changes such as
`machine_type` roll with new capacity first. New connections through an
attached load balancer remain available; sessions on the replaced instance drop.

GCP cannot roll a MIG across subnets. A subnet change requires one MIG
recreate; later rolling updates are unchanged.

## Disks

Attached disks mount at `/mnt/<device-name>`. Persistent disks across MIG
replace are not supported yet.

## Security

- Secret values are not in Terraform state, metadata, or the boot disk (IDs only).
- No VM public IP; operators use IAP.
- Per-secret Secret Manager IAM (not project-wide `secretAccessor`).
