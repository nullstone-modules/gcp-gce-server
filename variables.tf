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

variable "health_check_port" {
  type        = number
  default     = null
  description = <<EOF
TCP port on the VM that must accept connections for the instance to be considered healthy.
When set, the MIG recreates an instance that fails 3 consecutive probes (10 s interval, 300 s
grace after boot). Unset (default) disables auto-healing.
EOF

  validation {
    condition     = var.health_check_port == null || (var.health_check_port >= 1 && var.health_check_port <= 65535)
    error_message = "health_check_port must be between 1 and 65535."
  }
}
