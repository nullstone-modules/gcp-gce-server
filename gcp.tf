data "google_client_config" "this" {}
data "google_compute_zones" "available" {}

locals {
  project_id      = data.google_client_config.this.project
  region          = data.google_client_config.this.region
  available_zones = data.google_compute_zones.available.names
}

resource "google_project_service" "compute" {
  service                    = "compute.googleapis.com"
  disable_dependent_services = false
  disable_on_destroy         = false
}
