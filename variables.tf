variable "ssh_public_keys" {
  type        = map(string)
  description = <<EOF
A map of SSH public keys to add to the bastion's authorized_keys file.
This map should define a unique user name for the key mapped to the public key.
This is used to authorize each developer's identity for SSH access.
EOF
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  default     = []
  description = <<EOF
The IP Ranges for users that are allowed to access this server from the internet.
By default, this is empty which allows no IPv4 to access the box.
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