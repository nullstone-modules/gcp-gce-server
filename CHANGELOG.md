# 0.1.0

* `load_balancers` capability output is now a typed spec (`type = target_pool | tcp | http`; entries without `type` are target pools, so existing capabilities are unchanged). Server >= 0.1.0 is required for `gcp-gce-tcp-load-balancer` >= 0.1.0 and for `gcp-gce-http-load-balancer`.
* `tcp`: creates a regional TCP health check, `EXTERNAL` backend service on the MIG instance group, and forwarding rule on the capability's address.
* `http`: creates an HTTP health check, `EXTERNAL_MANAGED` backend service on a MIG named port, URL map, HTTPS proxy on the subdomain certificate map, and global forwarding rule on 443.
* One health-check firewall per attached type admitting Google's probe ranges to the probed port.
* Added `auto_healing_port`: optional MIG auto-healing on a TCP health check (default off).
* Added `tofu test` planning the capabilities.tf placeholder with one entry per type.
