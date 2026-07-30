locals {
  image_name = var.image_name == "" ? "ubuntu-os-cloud/ubuntu-2404-lts-amd64" : var.image_name

  instance_tags = [
    "ns-stack-${local.stack_name}",
    "ns-block-${local.block_name}",
    "ns-env-${local.env_name}",
  ]

  ssh_keys = join("\n", [for username, public_key in var.ssh_public_keys : "${username}:${public_key}"])

  # IAP TCP forwarding ranges for OS Login / gcloud SSH without a public IP.
  # https://cloud.google.com/iap/docs/using-tcp-forwarding
  iap_ssh_cidrs = [
    "35.235.240.0/20",
    "2600:2d00:1:7::/64",
  ]

  # Target pools from L4 LB capabilities; MIG registers instances into them.
  target_pools = [for lb in local.capabilities.load_balancers : lb.target_pool]
}

resource "google_compute_instance_template" "this" {
  name_prefix  = "${local.resource_name}-"
  machine_type = var.machine_type
  tags         = local.instance_tags
  labels       = local.labels

  service_account {
    email  = google_service_account.app.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  disk {
    source_image = local.image_name
    auto_delete  = true
    boot         = true
    disk_size_gb = var.boot_disk_gb
    disk_type    = var.boot_disk_type
  }

  # Attached persistent disks + MIG rolling replace is not solved here yet.
  # Kept so existing disk capabilities still wire; use with care until storage design lands.
  dynamic "disk" {
    for_each = local.disks

    content {
      source      = disk.value.disk_id
      device_name = disk.value.device_name
      mode        = disk.value.mode
      auto_delete = false
      boot        = false
    }
  }

  # No access_config: no VM public IP. SSH via IAP; app public IP comes from an L4 LB capability.
  network_interface {
    network    = local.vpc_name
    subnetwork = local.public_subnet_names[0]
  }

  metadata = {
    enable-oslogin = local.ssh_keys == "" ? "TRUE" : null
    ssh-keys       = local.ssh_keys
    user-data      = local.cloud_init
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Regional MIG across all available zones: size 1, surge = zone count / unavailable 0.
resource "google_compute_region_instance_group_manager" "this" {
  name               = local.resource_name
  base_instance_name = local.resource_name
  region             = local.region
  target_size        = 1
  target_pools       = local.target_pools

  version {
    instance_template = google_compute_instance_template.this.id
  }

  update_policy {
    type                           = "PROACTIVE"
    minimal_action                 = "REPLACE"
    most_disruptive_allowed_action = "REPLACE"
    # Regional fixed surge/unavailable must be 0 or >= number of zones.
    max_surge_fixed       = length(local.available_zones)
    max_unavailable_fixed = 0
    replacement_method    = "SUBSTITUTE"
  }

  distribution_policy_zones = local.available_zones

  depends_on = [google_project_service.compute]
}

resource "google_compute_firewall" "server-ssh" {
  name          = "${local.resource_name}-allow-ssh"
  network       = local.vpc_name
  source_ranges = local.iap_ssh_cidrs
  target_tags   = local.instance_tags

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
