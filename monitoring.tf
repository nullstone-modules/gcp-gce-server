data "ns_connection" "notification" {
  name     = "notification"
  contract = "datastore/gcp/notification"
  optional = true
}

locals {
  notification_name = try(data.ns_connection.notification.outputs.notification_name, "")
}

resource "google_monitoring_alert_policy" "cpu" {
  count = local.notification_name == "" ? 0 : 1

  display_name = "${local.resource_name}-cpu-utilization"
  combiner     = "OR"

  conditions {
    display_name = "CPU utilization above ${var.resource_thresholds.cpu}%"

    condition_threshold {
      filter          = "resource.type = \"gce_instance\" AND metric.type = \"compute.googleapis.com/instance/cpu/utilization\" AND resource.labels.instance_name = starts_with(\"${google_compute_region_instance_group_manager.this.base_instance_name}\")"
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.resource_thresholds.cpu / 100.0

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = [local.notification_name]

  alert_strategy {
    auto_close = "1800s"
  }
}
