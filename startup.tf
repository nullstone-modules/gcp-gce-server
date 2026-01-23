locals {
  cloud_config = yamlencode({
    write_files = [
      {
        path        = "/usr/local/bin/mount-disks.sh"
        permissions = "0755"
        owner       = "root:root"
        content     = file("${path.module}/mount-disks.sh")
      }
    ]

    runcmd = [
      # Run mount script with space-separated list of disk names
      "DISKS=\"${join(" ", local.disk_names)}\" /usr/local/bin/mount-disks.sh"
    ]
  })

  cloud_init = <<-EOT
#cloud-config
${local.cloud_config}
EOT
}
