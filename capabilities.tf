// This file is replaced by code-generation using 'capabilities.tf.tmpl'
// This file helps app module creators define a contract for what types of capability outputs are supported.
locals {
  cap_modules = [
    {
      name       = ""
      tfId       = ""
      namespace  = ""
      env_prefix = ""
      outputs    = {}

      meta = {
        subcategory = ""
        platform    = ""
        subplatform = ""
        outputNames = []
      }
    }
  ]

  // cap_env_prefixes is a map indexed by tfId which points to the env_prefix in local.cap_modules
  cap_env_prefixes = tomap({
    x = ""
  })

  capabilities = {
    env = [
      {
        cap_tf_id = "x"
        name      = ""
        value     = ""
      }
    ]

    secrets = [
      {
        cap_tf_id = "x"
        name      = ""
        value     = sensitive("")
      }
    ]

    // private_urls follows a wonky syntax so that we can send all capability outputs into the merge module
    // Terraform requires that all members be of type list(map(any))
    // They will be flattened into list(string) when we output from this module
    private_urls = [
      {
        cap_tf_id = "x"
        url       = "http://example"
      }
    ]

    // public_urls follows a wonky syntax so that we can send all capability outputs into the merge module
    // Terraform requires that all members be of type list(map(any))
    // They will be flattened into list(string) when we output from this module
    public_urls = [
      {
        cap_tf_id = "x"
        url       = "https://example.com"
      }
    ]

    // metrics allows capabilities to attach metrics to the application
    // These metrics are displayed on the Application Monitoring page
    // See https://docs.nullstone.io/extending/metrics/overview.html
    metrics = [
      {
        cap_tf_id = "x"
        name      = ""
        type      = "usage|usage-percent|duration|generic"
        unit      = ""

        mappings = jsonencode({})
      }
    ]

    disks = [
      {
        cap_tf_id   = "x"
        device_name = ""
        disk_id     = ""
        mode        = "" // "READ_WRITE" | "READ_ONLY"
      }
    ]

    cloud_init_stanzas = [
      {
        cap_tf_id = "x"
        write_files = [
          {
            path        = "/"
            permissions = "0644"
            owner       = "root:root"
            content     = "..."
          }
        ]
        runcmd = [
          "systemctl daemon-reload"
        ]
      }
    ]

    // secret_files lets capabilities materialize GSM secrets as files on tmpfs
    // (e.g. gcp-gce-mounted-ssh-keys). Consumed at local.capabilities.secret_files.
    secret_files = [
      {
        cap_tf_id = "x"
        name      = "id_ed25519"
        secret_id = "..."
      }
    ]

    // named_ports lets capabilities register MIG named ports (e.g. tcp LB).
    // Consumed on the regional MIG as dynamic named_port blocks.
    named_ports = [
      {
        cap_tf_id = "x"
        name      = "tcp-2022"
        port      = 2022
      }
    ]
  }
}
