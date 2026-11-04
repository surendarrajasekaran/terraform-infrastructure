provider "google" {
  project = var.gcp_project
  region  = var.region
}
locals {
  name   = "${var.name}-${var.environment}"
  ha     = var.environment == "production"
  labels = merge(var.labels, { project = var.name, environment = var.environment, managed_by = "terraform" })
}
module "gcp" {
  count                   = 1
  source                  = "../../../modules/gcp"
  name                    = local.name
  project                 = var.gcp_project
  region                  = var.region
  public_cluster_endpoint = var.public_cluster_endpoint
  admin_cidrs             = var.admin_cidrs
  ha                      = local.ha
  deletion_protection     = var.deletion_protection
  network_cidrs           = var.gcp_network_cidrs
  database_tier           = var.gcp_database_tier
  database                = var.database
  database_flags          = var.database_flags
  additional_gar_services = var.gcp_additional_gar_services
  gar_cleanup_dry_run     = var.gar_cleanup_dry_run
  github                  = var.github
  github_environment      = "gcp-${var.environment}"
  labels                  = local.labels
  flow_logs_enabled       = var.flow_logs_enabled
}

provider "helm" {
  kubernetes = {
    host                   = module.gcp[0].cluster_endpoint
    cluster_ca_certificate = try(base64decode(module.gcp[0].cluster_certificate_authority_data), null)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "gke-gcloud-auth-plugin"
      args        = ["--use_application_default_credentials"]
    }
  }
}
module "argocd" {
  source        = "../../../modules/gcp/argocd"
  chart_version = var.argocd_chart_version
  values        = [file("${path.module}/argocd-values.yaml")]
  depends_on    = [module.gcp]
}
