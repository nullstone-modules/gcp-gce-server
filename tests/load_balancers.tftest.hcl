# Plans the module against the load_balancers examples in capabilities.tf (one entry per type)
# and asserts the resource set per type, the MIG named port, and health-check firewalls.
# Run: tofu test

mock_provider "ns" {
  mock_data "ns_workspace" {
    defaults = {
      block_ref  = "app"
      stack_name = "primary"
      block_name = "app"
      env_name   = "dev"
      stack_id   = 1
      block_id   = 2
      env_id     = 3
      gcp_labels = { "nullstone-env" = "dev" }
    }
  }

  mock_data "ns_connection" {
    defaults = {
      outputs = {
        vpc_name             = "primary-vpc"
        private_subnet_names = ["primary-private-a"]
        public_subnet_names  = ["primary-public-a"]
        notification_name    = ""
      }
    }
  }

  mock_data "ns_app_env" {
    defaults = { version = "1.0.0", commit_sha = "abc123" }
  }

  mock_data "ns_env_variables" {
    defaults = { env_variables = {}, secrets = {}, secret_refs = {} }
  }

  mock_data "ns_secret_keys" {
    defaults = { secret_keys = [] }
  }
}

mock_provider "google" {
  mock_data "google_client_config" {
    defaults = { region = "us-central1", project = "proj" }
  }

  mock_data "google_project" {
    defaults = { number = "123456" }
  }

  mock_data "google_compute_zones" {
    defaults = { names = ["us-central1-a", "us-central1-b", "us-central1-c"] }
  }

  # The provider validates these formats at plan time; random mock strings fail.
  mock_resource "google_service_account" {
    defaults = {
      id    = "projects/proj/serviceAccounts/app-abcde@proj.iam.gserviceaccount.com"
      email = "app-abcde@proj.iam.gserviceaccount.com"
    }
  }

  mock_resource "google_compute_region_instance_group_manager" {
    defaults = { instance_group = "https://www.googleapis.com/compute/v1/projects/proj/regions/us-central1/instanceGroups/app-abcde" }
  }
}

mock_provider "random" {
  mock_resource "random_string" {
    defaults = { result = "abcde" }
  }
}


run "mixed_load_balancers" {
  command = plan

  # target_pool: MIG attaches directly, nothing else is created.
  assert {
    condition     = resource.google_compute_region_instance_group_manager.this.target_pools == toset(["https://www.googleapis.com/compute/v1/projects/<project>/regions/<region>/targetPools/<name>"])
    error_message = "MIG target_pools must list the target_pool entries"
  }

  # tcp passthrough: regional health check, backend service, forwarding rule keyed on the capability id.
  assert {
    condition     = keys(resource.google_compute_forwarding_rule.tcp) == ["sftp-ingress", "sftp-internal"] && keys(resource.google_compute_region_backend_service.tcp) == ["sftp-ingress", "sftp-internal"] && keys(resource.google_compute_region_health_check.tcp) == ["sftp-ingress", "sftp-internal"]
    error_message = "passthrough tcp entries must produce one regional health check, backend service, and forwarding rule each"
  }

  assert {
    condition     = resource.google_compute_region_backend_service.tcp["sftp-ingress"].network == null
    error_message = "external passthrough must not bind to the VPC subnet"
  }

  # tcp internal passthrough: INTERNAL scheme bound to the private subnet.
  assert {
    condition     = resource.google_compute_region_backend_service.tcp["sftp-internal"].load_balancing_scheme == "INTERNAL" && resource.google_compute_region_backend_service.tcp["sftp-internal"].network == "primary-vpc"
    error_message = "internal backend service must be INTERNAL on the VPC"
  }

  assert {
    condition     = resource.google_compute_forwarding_rule.tcp["sftp-internal"].load_balancing_scheme == "INTERNAL" && resource.google_compute_forwarding_rule.tcp["sftp-internal"].subnetwork == "primary-public-a" && resource.google_compute_forwarding_rule.tcp["sftp-internal"].ip_address == "10.0.1.10" && resource.google_compute_forwarding_rule.tcp["sftp-internal"].allow_global_access == true
    error_message = "internal forwarding rule must sit in the public (ingress) subnet with global access"
  }

  # tcp global: global health check, backend service on a named port, TCP proxy, global forwarding rule.
  assert {
    condition     = keys(resource.google_compute_global_forwarding_rule.tcp_global) == ["sftp-global"] && keys(resource.google_compute_target_tcp_proxy.tcp_global) == ["sftp-global"] && keys(resource.google_compute_backend_service.tcp_global) == ["sftp-global"] && keys(resource.google_compute_health_check.tcp_global) == ["sftp-global"]
    error_message = "global tcp entries must produce the global proxy chain"
  }

  assert {
    condition     = resource.google_compute_backend_service.tcp_global["sftp-global"].load_balancing_scheme == "EXTERNAL_MANAGED" && resource.google_compute_backend_service.tcp_global["sftp-global"].protocol == "TCP" && resource.google_compute_backend_service.tcp_global["sftp-global"].port_name == "tcp-2022"
    error_message = "global backend service must be EXTERNAL_MANAGED TCP on the named port"
  }

  assert {
    condition     = resource.google_compute_target_tcp_proxy.tcp_global["sftp-global"].proxy_header == "PROXY_V1" && resource.google_compute_global_forwarding_rule.tcp_global["sftp-global"].port_range == "22" && resource.google_compute_global_forwarding_rule.tcp_global["sftp-global"].ip_address == "203.0.113.30"
    error_message = "global chain must honour proxy_protocol, service_port, and the global address"
  }

  assert {
    condition     = resource.google_compute_region_health_check.tcp["sftp-ingress"].tcp_health_check[0].port == 2022 && resource.google_compute_region_health_check.tcp["sftp-ingress"].check_interval_sec == 5
    error_message = "tcp health check must probe server_port with the entry timings"
  }

  assert {
    condition     = [for b in resource.google_compute_region_backend_service.tcp["sftp-ingress"].backend : b.balancing_mode] == ["CONNECTION"] && resource.google_compute_region_backend_service.tcp["sftp-ingress"].load_balancing_scheme == "EXTERNAL"
    error_message = "tcp backend service must be EXTERNAL with CONNECTION balancing"
  }

  assert {
    condition     = resource.google_compute_forwarding_rule.tcp["sftp-ingress"].ports == toset(["22"]) && resource.google_compute_forwarding_rule.tcp["sftp-ingress"].ip_address == "203.0.113.10" && resource.google_compute_forwarding_rule.tcp["sftp-ingress"].name == "app-fghij-22"
    error_message = "tcp forwarding rule must expose service_port on the capability address"
  }

  # http: global health check, backend service, url map, https proxy, global forwarding rule.
  assert {
    condition     = keys(resource.google_compute_global_forwarding_rule.http) == ["web-ingress"] && keys(resource.google_compute_target_https_proxy.http) == ["web-ingress"] && keys(resource.google_compute_url_map.http) == ["web-ingress"] && keys(resource.google_compute_backend_service.http) == ["web-ingress"] && keys(resource.google_compute_health_check.http) == ["web-ingress"]
    error_message = "http entries must produce the full global LB chain"
  }

  assert {
    condition     = resource.google_compute_health_check.http["web-ingress"].http_health_check[0].port == 8080 && resource.google_compute_health_check.http["web-ingress"].http_health_check[0].request_path == "/healthz"
    error_message = "http health check must probe server_port at health_check.path"
  }

  assert {
    condition     = resource.google_compute_backend_service.http["web-ingress"].port_name == "http-8080" && resource.google_compute_backend_service.http["web-ingress"].load_balancing_scheme == "EXTERNAL_MANAGED" && [for b in resource.google_compute_backend_service.http["web-ingress"].backend : b.balancing_mode] == ["UTILIZATION"]
    error_message = "http backend service must be EXTERNAL_MANAGED on the named port"
  }

  assert {
    condition     = resource.google_compute_target_https_proxy.http["web-ingress"].certificate_map == "//certificatemanager.googleapis.com/projects/<project>/locations/global/certificateMaps/<name>"
    error_message = "https proxy must reference the certificate map from the entry"
  }

  assert {
    condition     = resource.google_compute_global_forwarding_rule.http["web-ingress"].port_range == "443" && resource.google_compute_global_forwarding_rule.http["web-ingress"].ip_address == "203.0.113.20" && resource.google_compute_global_forwarding_rule.http["web-ingress"].load_balancing_scheme == "EXTERNAL_MANAGED"
    error_message = "global forwarding rule must serve 443 on the capability address"
  }

  assert {
    condition     = toset([for np in resource.google_compute_region_instance_group_manager.this.named_port : "${np.name}:${np.port}"]) == toset(["http-8080:8080", "tcp-2022:2022"])
    error_message = "MIG must expose named ports for http and global tcp entries"
  }

  # Health-check ingress: one rule per type on the probed port, probe ranges only.
  assert {
    condition     = keys(resource.google_compute_firewall.health_check) == ["http", "tcp"]
    error_message = "one health-check firewall per attached type, none for the MIG check when unset"
  }

  assert {
    condition     = flatten([for a in resource.google_compute_firewall.health_check["tcp"].allow : a.ports]) == ["2022"] && flatten([for a in resource.google_compute_firewall.health_check["http"].allow : a.ports]) == ["8080"]
    error_message = "health-check firewalls must open only the probed ports"
  }

  assert {
    condition     = resource.google_compute_firewall.health_check["tcp"].source_ranges == toset(["35.191.0.0/16", "130.211.0.0/22", "209.85.152.0/22", "209.85.204.0/22"])
    error_message = "tcp health-check firewall must allow the external passthrough probe ranges (209.85.152.0/22, 209.85.204.0/22) plus the internal ones"
  }

  assert {
    condition     = resource.google_compute_firewall.health_check["http"].source_ranges == toset(["35.191.0.0/16", "130.211.0.0/22"])
    error_message = "http health-check firewall must allow only the proxied-LB probe ranges"
  }

  assert {
    condition     = length(resource.google_compute_health_check.liveness) == 0 && length(resource.google_compute_region_instance_group_manager.this.auto_healing_policies) == 0
    error_message = "auto-healing must be off by default"
  }
}

run "auto_healing" {
  command = plan

  variables {
    liveness_port = 2022
  }

  assert {
    condition     = length(resource.google_compute_health_check.liveness) == 1 && resource.google_compute_health_check.liveness[0].tcp_health_check[0].port == 2022
    error_message = "liveness_port must create a TCP health check"
  }

  assert {
    condition     = length(resource.google_compute_region_instance_group_manager.this.auto_healing_policies) == 1 && resource.google_compute_region_instance_group_manager.this.auto_healing_policies[0].initial_delay_sec == 300
    error_message = "MIG must get an auto-healing policy"
  }

  assert {
    condition     = keys(resource.google_compute_firewall.health_check) == ["http", "liveness", "tcp"] && flatten([for a in resource.google_compute_firewall.health_check["liveness"].allow : a.ports]) == ["2022"]
    error_message = "MIG health-check probes need their own firewall rule"
  }
}
