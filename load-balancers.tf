# Load balancers attached to the MIG, built from the load_balancers spec emitted by ingress
# capabilities (see README "Load balancers"). Capabilities own addresses, DNS, client firewalls,
# and cloud-init; this module owns everything that must name the MIG instance group, because a
# capability input derived from the MIG would be a module cycle.

locals {
  # Entries without `type` come from capability versions that predate the spec (target pools).
  lb_target_pools = [for lb in local.capabilities.load_balancers : lb if try(lb.type, "target_pool") == "target_pool"]

  # Keyed on the capability id, not lb.name: name carries the capability's random suffix, which
  # is unknown on the first apply, and for_each keys must be known at plan time. One entry per
  # capability instance.
  lb_tcp  = { for lb in local.capabilities.load_balancers : lb.cap_tf_id => lb if try(lb.type, "target_pool") == "tcp" }
  lb_http = { for lb in local.capabilities.load_balancers : lb.cap_tf_id => lb if try(lb.type, "target_pool") == "http" }

  target_pools = [for lb in local.lb_target_pools : lb.target_pool]

  # MIG named ports for HTTP backend services (port_name -> server_port).
  named_ports = { for lb in values(local.lb_http) : lb.port_name => lb.server_port }

  # Google health-check probe sources. For the global HTTPS LB these ranges also carry the
  # proxied client traffic, so one rule per type covers both.
  # https://cloud.google.com/load-balancing/docs/health-check-concepts#ip-ranges
  health_check_source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]

  health_check_ports = {
    tcp      = [for lb in values(local.lb_tcp) : lb.server_port]
    http     = [for lb in values(local.lb_http) : lb.server_port]
    autoheal = var.auto_healing_port == null ? [] : [var.auto_healing_port]
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

# --- type = "tcp": regional external passthrough NLB -----------------------------------------

resource "google_compute_region_health_check" "tcp" {
  for_each = local.lb_tcp

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
  for_each = local.lb_tcp

  name                  = each.value.name
  region                = local.region
  load_balancing_scheme = "EXTERNAL"
  protocol              = "TCP"
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
  for_each = local.lb_tcp

  name                  = "${each.value.name}-${each.value.service_port}"
  region                = local.region
  load_balancing_scheme = "EXTERNAL"
  ip_protocol           = "TCP"
  ports                 = [tostring(each.value.service_port)]
  ip_address            = each.value.ip_address
  backend_service       = google_compute_region_backend_service.tcp[each.key].id
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

# --- MIG auto-healing ------------------------------------------------------------------------

resource "google_compute_health_check" "auto_heal" {
  count = var.auto_healing_port == null ? 0 : 1

  name                = "${local.resource_name}-autoheal"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  tcp_health_check {
    port = var.auto_healing_port
  }
}
