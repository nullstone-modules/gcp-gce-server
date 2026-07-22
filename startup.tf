locals {
  cap_write_files = flatten([
    for s in lookup(local.capabilities, "cloud_init_stanzas", []) : try(s.content.write_files, [])
  ])
  cap_runcmd = flatten([
    for s in lookup(local.capabilities, "cloud_init_stanzas", []) : try(s.content.runcmd, [])
  ])

  # Non-sensitive env vars, rendered as a KEY=VALUE manifest. Each line carries a
  # trailing newline so the loader can cat it verbatim without gluing entries.
  app_env_manifest = join("", [for k, v in local.all_env_vars : "${k}=${v}\n"])

  # Secrets, rendered as a KEY=<secret_id> manifest. Only the Secret Manager
  # identifier is written -- never the secret value -- so no secret material
  # touches disk or Terraform state. load-app-secrets.sh resolves each id to its
  # value at boot into a tmpfs mount. Trailing newline per line for the loader.
  app_secrets_manifest = join("", [for k, id in local.all_secrets : "${k}=${id}\n"])

  manifest_write_files = [
    {
      path        = "/etc/app/env.manifest"
      permissions = "0640"
      owner       = "root:root"
      content     = local.app_env_manifest
    },
    {
      path        = "/etc/app/secrets.manifest"
      permissions = "0640"
      owner       = "root:root"
      content     = local.app_secrets_manifest
    },
    {
      path        = "/usr/local/bin/load-app-secrets.sh"
      permissions = "0755"
      owner       = "root:root"
      content     = file("${path.module}/load-app-secrets.sh")
    },
  ]

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
      ["/usr/local/bin/load-app-secrets.sh"],
      local.cap_runcmd,
    )
  })

  cloud_init = <<-EOT
#cloud-config
${local.cloud_config}
EOT
}
