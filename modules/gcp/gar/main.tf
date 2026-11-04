resource "google_artifact_registry_repository" "images" {
  for_each               = var.services
  project                = var.project
  location               = var.region
  repository_id          = "${var.name}-${each.key}"
  description            = "${var.name} ${each.key} container images"
  format                 = "DOCKER"
  labels                 = var.labels
  cleanup_policy_dry_run = var.cleanup_dry_run
  docker_config { immutable_tags = true }
  cleanup_policies {
    id     = "delete-old-untagged"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "${var.untagged_retention_days * 86400}s"
    }
  }
  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions { keep_count = 20 }
  }
}
resource "google_artifact_registry_repository_iam_member" "reader" {
  for_each   = google_artifact_registry_repository.images
  project    = var.project
  location   = var.region
  repository = each.value.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${var.node_service_account_email}"
}
