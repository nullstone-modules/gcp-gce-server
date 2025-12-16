resource "google_compute_address" "this" {
  name   = local.resource_name
  region = local.region
  labels = local.labels
}

locals {
  public_ip = google_compute_address.this.address
}
