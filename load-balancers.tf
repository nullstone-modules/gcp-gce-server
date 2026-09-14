# Load balancers attached to the MIG, built from the load_balancers spec emitted by ingress
# capabilities (see README "Load balancers"). Capabilities own addresses, DNS, client firewalls,
# and cloud-init; this module owns everything that must name the MIG instance group, because a
# capability input derived from the MIG would be a module cycle.

locals {
  # Entries without `type` come from capability versions that predate the spec (target pools).
  # Legacy: no health check, and the MIG silently loses the pool when it is recreated. Kept only
  # so existing attachments survive an upgrade; new capabilities must emit tcp or http.
  lb_target_pools = [for lb in local.capabilities.load_balancers : lb if try(lb.type, "target_pool") == "target_pool"]

  # Keyed on the capability id, not lb.name: name carries the capability's random suffix, which
  # is unknown on the first apply, and for_each keys must be known at plan time. One entry per
  # capability instance. Variant flags default to the plain external form.
  lb_tcp = {
    for lb in local.capabilities.load_balancers : lb.cap_tf_id => merge({
      scheme         = "EXTERNAL"
      global         = false
      proxy_protocol = false
      port_name      = "tcp-${lb.server_port}"
    }, lb) if try(lb.type, "target_pool") == "tcp"
  }
  lb_http = {
    for lb in local.capabilities.load_balancers : lb.cap_tf_id => merge({
      scope  = "global"
      scheme = "EXTERNAL_MANAGED"
    }, lb) if try(lb.type, "target_pool") == "http"
  }

  # tcp variants: regional passthrough (EXTERNAL or INTERNAL) or global, which is proxied.
  lb_tcp_passthrough = { for k, lb in local.lb_tcp : k => lb if !lb.global }
  lb_tcp_global      = { for k, lb in local.lb_tcp : k => lb if lb.global }

  # Variants that need a proxy-only subnet in the VPC, which gcp-network does not create yet.
  lb_unsupported = concat(
    [for k, lb in local.lb_tcp : "${k} (internal global tcp)" if lb.global && lb.scheme == "INTERNAL"],
    [for k, lb in local.lb_http : "${k} (${lb.scope} ${lb.scheme} http)" if lb.scope != "global" || lb.scheme != "EXTERNAL_MANAGED"],
  )

  target_pools = [for lb in local.lb_target_pools : lb.target_pool]

  # MIG named ports for global backend services (port_name -> server_port).
  named_ports = merge(
    { for lb in values(local.lb_http) : lb.port_name => lb.server_port },
    { for lb in values(local.lb_tcp_global) : lb.port_name => lb.server_port },
  )

  # Google health-check probe sources. Proxied load balancers (http, global tcp) also deliver
  # client traffic from these ranges, so one rule per type covers both.
  # https://cloud.google.com/load-balancing/docs/health-check-concepts#ip-ranges
  health_check_source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]

  health_check_ports = {
    tcp      = [for lb in values(local.lb_tcp) : lb.server_port]
    http     = [for lb in values(local.lb_http) : lb.server_port]
    liveness = var.liveness_port == null ? [] : [var.liveness_port]
  }
  health_check_firewalls = { for type, ports in local.health_check_ports : type => distinct(ports) if length(ports) > 0 }
}

resource "google_compute_firewall" "health_check" {
  for_each = local.health_check_firewalls

  name          = "${local.resource_name}-allow-hc-${each.key}"
  network       = local.vpc_name
  source_ranges = local.health_check_source_ranges
  target_tags   = local.instance_tags

  allow {
    protocol = "tcp"
    ports    = [for p in each.value : tostring(p)]
  }
}

# --- type = "tcp", passthrough: regional external or internal NLB ------------------------------

resource "google_compute_region_health_check" "tcp" {
  for_each = local.lb_tcp_passthrough

  name                = each.value.name
  region              = local.region
  check_interval_sec  = each.value.health_check.interval_sec
  timeout_sec         = each.value.health_check.timeout_sec
  healthy_threshold   = each.value.health_check.healthy_threshold
  unhealthy_threshold = each.value.health_check.unhealthy_threshold

  tcp_health_check {
    port = each.value.server_port
  }
}

resource "google_compute_region_backend_service" "tcp" {
  for_each = local.lb_tcp_passthrough

  name                  = each.value.name
  region                = local.region
  load_balancing_scheme = each.value.scheme
  protocol              = "TCP"
  network               = each.value.scheme == "INTERNAL" ? local.vpc_name : null
  health_checks         = [google_compute_region_health_check.tcp[each.key].id]

  backend {
    group = google_compute_region_instance_group_manager.this.instance_group
    # Passthrough NLBs accept only CONNECTION; the provider default is UTILIZATION.
    balancing_mode = "CONNECTION"
  }
}

# Suffixed with the port so it cannot collide with a capability-owned forwarding rule of the
# same base name being deleted in the same apply (upgrading the tcp capability from 0.0.x).
resource "google_compute_forwarding_rule" "tcp" {
  for_each = local.lb_tcp_passthrough

  name                  = "${each.value.name}-${each.value.service_port}"
  region                = local.region
  load_balancing_scheme = each.value.scheme
  ip_protocol           = "TCP"
  ports                 = [tostring(each.value.service_port)]
  ip_address            = each.value.ip_address
  backend_service       = google_compute_region_backend_service.tcp[each.key].id
  network               = each.value.scheme == "INTERNAL" ? local.vpc_name : null
  subnetwork            = each.value.scheme == "INTERNAL" ? local.public_subnet_names[0] : null
  # Internal: reachable from clients in any region (VPN, peering, tailnet exit nodes).
  allow_global_access = each.value.scheme == "INTERNAL" ? true : null
  labels              = local.labels
}

# --- type = "tcp", global = true: global external proxy NLB (no passthrough) --------------------

resource "google_compute_health_check" "tcp_global" {
  for_each = local.lb_tcp_global

  name                = each.value.name
  check_interval_sec  = each.value.health_check.interval_sec
  timeout_sec         = each.value.health_check.timeout_sec
  healthy_threshold   = each.value.health_check.healthy_threshold
  unhealthy_threshold = each.value.health_check.unhealthy_threshold

  tcp_health_check {
    port = each.value.server_port
  }
}

resource "google_compute_backend_service" "tcp_global" {
  for_each = local.lb_tcp_global

  name                  = each.value.name
  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = "TCP"
  port_name             = each.value.port_name
  timeout_sec           = 30
  health_checks         = [google_compute_health_check.tcp_global[each.key].id]

  backend {
    group           = google_compute_region_instance_group_manager.this.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

resource "google_compute_target_tcp_proxy" "tcp_global" {
  for_each = local.lb_tcp_global

  name            = each.value.name
  backend_service = google_compute_backend_service.tcp_global[each.key].id
  proxy_header    = each.value.proxy_protocol ? "PROXY_V1" : "NONE"
}

resource "google_compute_global_forwarding_rule" "tcp_global" {
  for_each = local.lb_tcp_global

  name                  = "${each.value.name}-${each.value.service_port}"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_protocol           = "TCP"
  port_range            = tostring(each.value.service_port)
  ip_address            = each.value.ip_address
  target                = google_compute_target_tcp_proxy.tcp_global[each.key].id
  labels                = local.labels
}

# --- type = "http": global external Application LB, HTTPS only --------------------------------

resource "google_compute_health_check" "http" {
  for_each = local.lb_http

  name                = each.value.name
  check_interval_sec  = each.value.health_check.interval_sec
  timeout_sec         = each.value.health_check.timeout_sec
  healthy_threshold   = each.value.health_check.healthy_threshold
  unhealthy_threshold = each.value.health_check.unhealthy_threshold

  http_health_check {
    port         = each.value.server_port
    request_path = each.value.health_check.path
  }
}

resource "google_compute_backend_service" "http" {
  for_each = local.lb_http

  name                  = each.value.name
  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = "HTTP"
  port_name             = each.value.port_name
  timeout_sec           = 30
  health_checks         = [google_compute_health_check.http[each.key].id]

  backend {
    group           = google_compute_region_instance_group_manager.this.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

resource "google_compute_url_map" "http" {
  for_each = local.lb_http

  name            = each.value.name
  default_service = google_compute_backend_service.http[each.key].id
}

resource "google_compute_target_https_proxy" "http" {
  for_each = local.lb_http

  name            = each.value.name
  url_map         = google_compute_url_map.http[each.key].id
  certificate_map = "//certificatemanager.googleapis.com/${each.value.certificate_map_id}"
}

resource "google_compute_global_forwarding_rule" "http" {
  for_each = local.lb_http

  name                  = "${each.value.name}-443"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_protocol           = "TCP"
  port_range            = "443"
  ip_address            = each.value.ip_address
  target                = google_compute_target_https_proxy.http[each.key].id
  labels                = local.labels
}

# --- Liveness: MIG health check that recreates a failing instance --------------------------

resource "google_compute_health_check" "liveness" {
  count = var.liveness_port == null ? 0 : 1

  name                = "${local.resource_name}-liveness"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  tcp_health_check {
    port = var.liveness_port
  }
}
