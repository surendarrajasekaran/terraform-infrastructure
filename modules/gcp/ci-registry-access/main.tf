resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project
  workload_identity_pool_id = "${substr(var.name, 0, 18)}-${substr(sha256(var.name), 0, 5)}-github"
  display_name              = "${substr(var.name, 0, 18)} GitHub"
}
locals {
  subject_prefix = coalesce(var.github.subject_prefix, "repo:${var.github.repository}")
}
resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  attribute_mapping = {
    "google.subject"                = "assertion.sub"
    "attribute.repository_id"       = "assertion.repository_id"
    "attribute.repository_owner_id" = "assertion.repository_owner_id"
    "attribute.ref"                 = "assertion.ref"
  }
  attribute_condition = "assertion.repository_id == '${var.github.repository_id}' && assertion.repository_owner_id == '${var.github.owner_id}' && assertion.sub == '${local.subject_prefix}:environment:${var.github_environment}' && assertion.ref == 'refs/heads/${var.github.branch}'"
  oidc { issuer_uri = "https://token.actions.githubusercontent.com" }
}
resource "google_service_account" "publisher" {
  project      = var.project
  account_id   = "${substr(var.name, 0, 18)}-${substr(sha256(var.name), 0, 5)}-ci"
  display_name = "${var.name} repository-scoped image publisher"
}
resource "google_service_account_iam_member" "federation" {
  service_account_id = google_service_account.publisher.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository_id/${var.github.repository_id}"
  depends_on         = [google_iam_workload_identity_pool_provider.github]
}
resource "google_artifact_registry_repository_iam_member" "publisher" {
  for_each   = var.repository_ids
  project    = var.project
  location   = var.region
  repository = each.value
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.publisher.email}"
}
