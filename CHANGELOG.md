# 0.1.0

* `load_balancers` capability output is now a typed spec (`type = tcp | http`; entries without `type` are `{ port, target_pool }` from older tcp capabilities and still set MIG `target_pools`, so existing attachments are unchanged). Target pools are legacy: no health check, and a recreated pool is silently dropped by the MIG. Kept for upgrades only; do not use for new capabilities. Server >= 0.1.0 is required for `gcp-gce-tcp-load-balancer` >= 0.1.0 and for `gcp-gce-http-load-balancer`.
* `tcp` entries carry variant flags: `scheme` (`EXTERNAL` or `INTERNAL` passthrough) and `global` (global external proxy NLB with optional `proxy_protocol`, on a MIG named port). `http` entries carry `scope` and `scheme`; only `global` + `EXTERNAL_MANAGED` is implemented, other combinations fail the plan until gcp-network provides a proxy-only subnet. `app_metadata.lb_subnet` (first public subnet) is now provided for internal load balancer addresses.
* `tcp`: creates a regional TCP health check, `EXTERNAL` backend service on the MIG instance group, and forwarding rule on the capability's address.
* `http`: creates an HTTP health check, `EXTERNAL_MANAGED` backend service on a MIG named port, URL map, HTTPS proxy on the subdomain certificate map, and global forwarding rule on 443.
* One health-check firewall per attached type admitting Google's probe ranges to the probed port.
* Added `liveness_port`: optional TCP liveness check; a failing instance is recreated (`0`, the default, is off).
* Added `tofu test` planning the capabilities.tf placeholder with one entry per type.
