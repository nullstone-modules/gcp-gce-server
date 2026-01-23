locals {
  disks      = local.capabilities.disks
  disk_names = [for disk in local.disks : disk.device_name]
}
