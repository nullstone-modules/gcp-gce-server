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

## Load balancers (`load_balancers` capability output)

Ingress capabilities emit a spec; this module creates whatever must name the MIG instance group.
A capability cannot reference the MIG itself (each capability is consumed as a whole object, so
a MIG-derived input is a module cycle). Capabilities keep the address, DNS, client firewall,
`public_urls`, and cloud-init.

| `type` | Capability | Server creates |
|--------|------------|----------------|
| (none) | `gcp-gce-tcp-load-balancer` < 0.1.0 | nothing; MIG `target_pools` lists `target_pool`. Legacy: no health check, and the MIG silently drops a recreated pool. Kept so existing attachments survive an upgrade; do not use for new capabilities |
| `tcp` | `gcp-gce-tcp-load-balancer` >= 0.1.0 | `google_compute_region_health_check` (TCP on `server_port`), `google_compute_region_backend_service` (`EXTERNAL`, `TCP`, `CONNECTION`), `google_compute_forwarding_rule` `<name>-<service_port>` on `ip_address` |
| `http` | `gcp-gce-http-load-balancer` | `google_compute_health_check` (HTTP `health_check.path` on `server_port`), `google_compute_backend_service` (`EXTERNAL_MANAGED`, `HTTP`, `port_name`), `google_compute_url_map`, `google_compute_target_https_proxy` (`certificate_map_id`), `google_compute_global_forwarding_rule` `<name>-443` on `ip_address`; MIG named port `port_name` → `server_port` |

Entry shapes:

```hcl
{ port = "22", target_pool = "<self_link>" }   # legacy, gcp-gce-tcp-load-balancer < 0.1.0; no type field; avoid

{
  type         = "tcp"
  name         = "<res name>"
  ip_address   = "<regional external address>"
  service_port = 22
  server_port  = 2022
  health_check = { interval_sec = 5, timeout_sec = 4, healthy_threshold = 2, unhealthy_threshold = 2 }
}

{
  type               = "http"
  name               = "<res name>"
  ip_address         = "<global external address>"
  certificate_map_id = "projects/<project>/locations/global/certificateMaps/<name>"
  port_name          = "http-8080"
  server_port        = 8080
  health_check       = { path = "/healthz", interval_sec = 5, timeout_sec = 4, healthy_threshold = 2, unhealthy_threshold = 2 }
}
```

`tcp` and `http` resources are keyed on the capability id (one entry per capability instance)
and named from `name`. Health-check ingress: one firewall rule per type,
`<name>-allow-hc-<type>`, allowing `35.191.0.0/16` and `130.211.0.0/22` to the probed
`server_port` on the instance tags. For `http` those ranges also carry the proxied client
traffic. Nothing else is opened.

The capabilities.tf placeholder lists one example entry per type; `tests/load_balancers.tftest.hcl`
plans against it.

### Manual verification

```bash
gcloud compute backend-services get-health <name> --region <region>   # tcp
gcloud compute backend-services get-health <name> --global            # http
```

Expect `healthState: HEALTHY`. Then hit the listener: `ssh-keyscan -p <service_port> <ip>` for
a TCP service, `curl -sI https://<fqdn>` for HTTP.

## MIG health check (`health_check_port`)

Unset by default. When set, a TCP health check on that port (10 s interval, 3 failures) is
attached to the MIG with a 300 s boot grace period, and a firewall rule
`<name>-allow-hc-mig` admits the probe ranges to that port. A failing instance is recreated. This is
the VM liveness check and is independent of any load balancer health check.

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

### Upgrading to 0.1.0

Server >= 0.1.0 is required for `gcp-gce-tcp-load-balancer` >= 0.1.0 and for
`gcp-gce-http-load-balancer`; older servers ignore those entries and attach nothing. Existing
`target_pool` attachments from older tcp capability versions keep working. Upgrading the tcp
capability recreates its forwarding rule on the same address: about 30–60 s of refused
connections on `service_port`. If that apply fails with "IP address ... is already in use", the
new rule was created before the old one finished deleting; apply again.

## Disks

Attached disks mount at `/mnt/<device-name>`. Persistent disks across MIG
replace are not supported yet.

## Security

- Secret values are not in Terraform state, metadata, or the boot disk (IDs only).
- No VM public IP; operators use IAP.
- Per-secret Secret Manager IAM (not project-wide `secretAccessor`).

## Tests

```bash
tofu test
bash tests/load-app-secrets-secret-files.sh   # needs python3
```
