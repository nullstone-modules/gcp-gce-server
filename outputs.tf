output "private_urls" {
  value       = local.private_urls
  description = "list(string) ||| A list of URLs only accessible inside the network"
}

output "public_urls" {
  value       = local.public_urls
  description = "list(string) ||| A list of URLs accessible to the public"
}

output "region" {
  value       = local.region
  description = "string ||| The GCP region where the instance is located"
}

output "zone" {
  value       = google_compute_instance.this.zone
  description = "string ||| The GCP zone where the instance is located"
}
