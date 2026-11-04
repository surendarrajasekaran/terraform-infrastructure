output "repository_urls" {
  value = { for service, repository in google_artifact_registry_repository.images : service => "${var.region}-docker.pkg.dev/${var.project}/${repository.repository_id}/${service}" }
}
output "repository_ids" { value = { for service, repository in google_artifact_registry_repository.images : service => repository.repository_id } }
output "registry_host" { value = "${var.region}-docker.pkg.dev" }
