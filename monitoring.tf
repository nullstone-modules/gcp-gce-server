resource "google_monitoring_notification_channel" "email" {
  count = var.resource_alerts.enabled ? 1 : 0

  display_name = "${local.resource_name}-email"
  type         = "email"
  labels = {
    email_address = var.resource_alerts.email
  }
}

resource "google_monitoring_alert_policy" "cpu" {
  count = var.resource_alerts.enabled ? 1 : 0

  display_name = "${local.resource_name}-cpu-utilization"
  combiner     = "OR"

  conditions {
    display_name = "CPU utilization above ${var.resource_alerts.cpu}%"

    condition_threshold {
      filter          = "resource.type = \"gce_instance\" AND resource.labels.instance_id = \"${google_compute_instance.this.instance_id}\" AND metric.type = \"compute.googleapis.com/instance/cpu/utilization\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.resource_alerts.cpu / 100.0

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email[0].name]

  alert_strategy {
    auto_close = "1800s"
  }
}
