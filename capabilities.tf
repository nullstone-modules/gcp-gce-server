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
        name      = "ENV_NAME"
        value     = ""
      }
    ]

    secrets = [
      {
        cap_tf_id = "x"
        name      = "SECRET_NAME"
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

    // load_balancers: ingress capabilities emit a spec; `type` selects the shape and this module
    // creates whatever must name the MIG instance group (see load-balancers.tf and README).
    // Entries without `type` are target pools from gcp-gce-tcp-load-balancer < 0.1.0, which emitted
    // { port, target_pool }; only target_pool is read. Legacy: target pools have no health check and
    // silently lose members when recreated. Kept only so existing attachments survive an upgrade;
    // do not build new capabilities on it.
    load_balancers = [
      {
        cap_tf_id = "legacy-ingress"
        port      = "2222"
        # The full URL of all target pools to which new instances in the group are added. Updating the target pools attribute does not affect existing instances.
        target_pool = "https://www.googleapis.com/compute/v1/projects/<project>/regions/<region>/targetPools/<name>"
      },
      {
        cap_tf_id    = "sftp-ingress"
        type         = "tcp"
        name         = "app-fghij"
        ip_address   = "203.0.113.10" # regional external address
        service_port = 22             # external port on the forwarding rule
        server_port  = 2022           # port probed on the VM
        health_check = {
          interval_sec        = 5
          timeout_sec         = 4
          healthy_threshold   = 2
          unhealthy_threshold = 2
        }
      },
      {
        cap_tf_id          = "web-ingress"
        type               = "http"
        name               = "app-klmno"
        ip_address         = "203.0.113.20" # global external address
        certificate_map_id = "projects/<project>/locations/global/certificateMaps/<name>"
        port_name          = "http-8080" # MIG named port
        server_port        = 8080
        health_check = {
          path                = "/healthz"
          interval_sec        = 5
          timeout_sec         = 4
          healthy_threshold   = 2
          unhealthy_threshold = 2
        }
      },
    ]
  }
}
