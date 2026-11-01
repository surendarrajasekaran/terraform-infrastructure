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
  labels                  = local.labels
  flow_logs_enabled       = var.flow_logs_enabled
}
