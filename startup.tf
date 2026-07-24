locals {
  # Capability-contributed cloud-init fragments (write_files / runcmd).
  cap_write_files = flatten([
    for s in lookup(local.capabilities, "cloud_init_stanzas", []) : try(s.content.write_files, [])
  ])
  cap_runcmd = flatten([
    for s in lookup(local.capabilities, "cloud_init_stanzas", []) : try(s.content.runcmd, [])
  ])

  # Trailing newline per line so the loader can cat manifests without gluing entries.
  app_env_manifest = join("", [for k, v in local.all_env_vars : "${k}=${v}\n"])
  # IDs only — never secret values (resolved at boot into tmpfs by load-app-secrets.sh).
  app_secrets_manifest = join("", [for k, id in local.all_secrets : "${k}=${id}\n"])

  manifest_write_files = [
    {
      path        = "/app/env.manifest"
      permissions = "0640"
      owner       = "root:root"
      content     = local.app_env_manifest
    },
    {
      path        = "/app/secrets.manifest"
      permissions = "0640"
      owner       = "root:root"
      content     = local.app_secrets_manifest
    },
    {
      path        = "/app/load-app-secrets.sh"
      permissions = "0755"
      owner       = "root:root"
      content     = file("${path.module}/load-app-secrets.sh")
    },
  ]

  # Loader runs before capability runcmd so app.env exists when workloads start.
  cloud_config = yamlencode({
    write_files = concat(
      [
        {
          path        = "/usr/local/bin/mount-disks.sh"
          permissions = "0755"
          owner       = "root:root"
          content     = file("${path.module}/mount-disks.sh")
        }
      ],
      local.manifest_write_files,
      local.cap_write_files,
    )
    runcmd = concat(
      ["DISKS=\"${join(" ", local.disk_names)}\" /usr/local/bin/mount-disks.sh"],
      ["/app/load-app-secrets.sh"],
      local.cap_runcmd,
    )
  })

  cloud_init = <<-EOT
#cloud-config
${local.cloud_config}
EOT
}
