locals {
  image_name = var.image_name == "" ? "ubuntu-os-cloud/ubuntu-2404-lts-amd64" : var.image_name

  instance_tags = [
    "ns-stack-${local.stack_name}",
    "ns-block-${local.block_name}",
    "ns-env-${local.env_name}",
  ]

  ssh_keys = join("\n", [for username, public_key in var.ssh_public_keys : "${username}:${public_key}"])

  # Named port on the MIG for L4 LB capabilities (passthrough uses this host port).
  service_port_name = "app"

  # IAP TCP forwarding range for OS Login / gcloud SSH without a public IP.
  iap_ssh_cidr = "35.235.240.0/20"
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

# Regional MIG, single zone: size 1, surge 1 / unavailable 0 (zero-downtime replace).
resource "google_compute_region_instance_group_manager" "this" {
  name               = local.resource_name
  base_instance_name = local.resource_name
  region             = local.region
  target_size        = 1

  version {
    instance_template = google_compute_instance_template.this.id
  }

  named_port {
    name = local.service_port_name
    port = var.service_port
  }

  update_policy {
    type                           = "PROACTIVE"
    minimal_action                 = "REPLACE"
    most_disruptive_allowed_action = "REPLACE"
    max_surge_fixed                = 1
    max_unavailable_fixed          = 0
    replacement_method             = "SUBSTITUTE"
  }

  distribution_policy_zones = [local.available_zones[0]]

  depends_on = [google_project_service.compute]
}

resource "google_compute_firewall" "server-ssh" {
  name          = "${local.resource_name}-allow-ssh"
  network       = local.vpc_name
  source_ranges = distinct(concat([local.iap_ssh_cidr], var.allowed_cidr_blocks, var.allowed_ipv6_cidr_blocks))
  target_tags   = local.instance_tags

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
