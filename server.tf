locals {
  image_name = var.image_name == "" ? "ubuntu-os-cloud/ubuntu-2404-lts-amd64" : var.image_name

  instance_tags = [
    "ns-stack-${local.stack_name}",
    "ns-block-${local.block_name}",
    "ns-env-${local.env_name}",
  ]

  ssh_keys = join("\n", [for username, public_key in var.ssh_public_keys : "${username}:${public_key}"])
}

resource "google_compute_instance" "this" {
  name         = local.resource_name
  machine_type = var.machine_type
  zone         = local.available_zones[0]
  tags         = local.instance_tags
  labels       = local.labels

  boot_disk {
    initialize_params {
      image = local.image_name
      size  = var.boot_disk_gb
      type  = var.boot_disk_type
    }
  }

  network_interface {
    network    = local.vpc_name
    subnetwork = local.public_subnet_names[0]

    access_config {
      nat_ip = local.public_ip
    }
  }

  metadata = {
    enable-oslogin = local.ssh_keys == "" ? "TRUE" : null
    ssh-keys       = local.ssh_keys
  }
}

resource "google_compute_firewall" "server-ssh" {
  name          = "${local.resource_name}-allow-ssh"
  network       = local.vpc_name
  source_ranges = concat(var.allowed_cidr_blocks, var.allowed_ipv6_cidr_blocks)
  target_tags   = local.instance_tags

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
