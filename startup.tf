locals {
  cloud_init_stanzas = try(local.capabilities.cloud_init_stanzas, [])
  secret_files       = try(local.capabilities.secret_files, [])

  # COS root (/) is read-only. /etc is writable + executable (stateless tmpfs);
  # cloud-init rewrites these files on every boot, which matches that model.
  nullstone_dir = "/etc/nullstone"

  # Capability-contributed cloud-init fragments (write_files / runcmd).
  cap_write_files = flatten([
    for s in local.cloud_init_stanzas : try(s.write_files, [])
  ])
  cap_runcmd = flatten([
    for s in local.cloud_init_stanzas : try(s.runcmd, [])
  ])

  # Trailing newline per line so the loader can cat manifests without gluing entries.
  app_env_manifest = join("", [for k, v in local.all_env_vars : "${k}=${v}\n"])
  # IDs only — never secret values (resolved at boot into tmpfs by load-app-secrets.sh).
  app_secrets_manifest = join("", [for k, id in local.all_secrets : "${k}=${id}\n"])
  # Capability-contributed file secrets (e.g. gcp-gce-mounted-ssh-keys).
  app_secret_files_manifest = join("", [
    for item in local.secret_files : "${item.name}=${item.secret_id}\n"
  ])

  # Server built-ins live under /etc/nullstone (not /app — that path is not writable on COS).
  manifest_write_files = [
    {
      path        = "${local.nullstone_dir}/env.manifest"
      permissions = "0640"
      owner       = "root:root"
      content     = local.app_env_manifest
    },
    {
      path        = "${local.nullstone_dir}/secrets.manifest"
      permissions = "0640"
      owner       = "root:root"
      content     = local.app_secrets_manifest
    },
    {
      path        = "${local.nullstone_dir}/secret-files.manifest"
      permissions = "0640"
      owner       = "root:root"
      content     = local.app_secret_files_manifest
    },
    {
      path        = "${local.nullstone_dir}/load-app-secrets.sh"
      permissions = "0755"
      owner       = "root:root"
      content     = file("${path.module}/load-app-secrets.sh")
    },
    {
      path        = "${local.nullstone_dir}/mount-disks.sh"
      permissions = "0755"
      owner       = "root:root"
      content     = file("${path.module}/mount-disks.sh")
    },
  ]

  # Loader runs before capability runcmd so app.env exists when workloads start.
  cloud_config = yamlencode({
    write_files = concat(
      local.manifest_write_files,
      local.cap_write_files,
    )
    runcmd = concat(
      ["DISKS=\"${join(" ", local.disk_names)}\" ${local.nullstone_dir}/mount-disks.sh"],
      ["${local.nullstone_dir}/load-app-secrets.sh"],
      local.cap_runcmd,
    )
  })

  cloud_init = <<-EOT
#cloud-config
${local.cloud_config}
EOT
}
