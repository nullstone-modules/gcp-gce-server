variable "ssh_public_keys" {
  type        = map(string)
  default     = {} // Empty map enables oslogin instead of configuring ssh keys
  description = <<EOF
A map of SSH public keys to add to the bastion's authorized_keys file.
This map should define a unique user name for the key mapped to the public key.
This is used to authorize each developer's identity for SSH access.
By specifying an empty map, oslogin will be enabled instead of configuring ssh keys.
EOF
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  default     = []
  description = <<EOF
Extra IPv4 ranges allowed to SSH (TCP 22), in addition to the IAP range (always allowed).
Instances have no public IP; use IAP for SSH: gcloud compute ssh --tunnel-through-iap
EOF
}

variable "allowed_ipv6_cidr_blocks" {
  type        = list(string)
  default     = []
  description = <<EOF
The IPv6 IP Ranges for users that are allowed to access this server from the internet.
By default, this is empty which allows no IPv6 access to the box.
EOF
}

variable "image_name" {
  type        = string
  default     = ""
  description = <<EOF
By default, this module uses the latest image from "ubuntu-os-cloud/ubuntu-2404-lts-amd64".
Use this variable to override the image name for the created instance.
EOF
}

variable "machine_type" {
  type        = string
  default     = "e2-standard-4"
  description = <<EOF
The machine type for the server.
EOF
}

variable "service_port" {
  type        = number
  default     = 2022
  description = <<EOF
TCP port the workload listens on on the VM.
Registered as MIG named port "app" so an L4 load-balancer capability can target it.
For passthrough L4, the LB forwarding port must match this host port (and docker host_port).
EOF
}

variable "boot_disk_gb" {
  type        = number
  default     = 50
  description = <<EOF
This initializes the boot disk with the specified size in GB.
EOF
}

variable "boot_disk_type" {
  type        = string
  default     = "pd-balanced"
  description = <<EOF
This initializes the boot disk with the specified type of disk.
Available options are: pd-ssd, pd-standard, pd-balanced
EOF
}

variable "resource_thresholds" {
  type = object({
    cpu = number
  })
  default = {
    cpu = 90
  }

  description = <<EOF
Configure CPU utilization alerting for the VM.
When enabled, a GCP monitoring alert policy is created that notifies the given notification channel when CPU utilization exceeds the configured threshold (0-100).
EOF
}
