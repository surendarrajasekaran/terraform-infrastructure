module "network" {
  source            = "./network"
  name              = var.name
  project           = var.project
  region            = var.region
  cidrs             = var.network_cidrs
  flow_logs_enabled = var.flow_logs_enabled
}
module "kubernetes" {
  source                  = "./kubernetes"
  depends_on              = [module.network]
  name                    = var.name
  project                 = var.project
  region                  = var.region
  network_id              = module.network.ready
  subnetwork_id           = module.network.subnetwork_id
  master_cidr             = var.network_cidrs.master
  public_cluster_endpoint = var.public_cluster_endpoint
  admin_cidrs             = var.admin_cidrs
  deletion_protection     = var.deletion_protection
  labels                  = var.labels
}
module "postgres" {
  source              = "./postgres"
  project             = var.project
  name                = var.name
  region              = var.region
  network_id          = module.network.ready
  ha                  = var.ha
  database_flags      = var.database_flags
  tier                = var.database_tier
  database            = var.database
  deletion_protection = var.deletion_protection
  labels              = var.labels
}

module "gar" {
  source                     = "./gar"
  name                       = var.name
  project                    = var.project
  region                     = var.region
  services                   = setunion(toset(["frontend", "backend"]), var.additional_gar_services)
  node_service_account_email = module.kubernetes.node_service_account_email
  cleanup_dry_run            = var.gar_cleanup_dry_run
  labels                     = var.labels
  depends_on                 = [module.network]
}

module "ci_registry_access" {
  count              = var.github == null ? 0 : 1
  source             = "./ci-registry-access"
  name               = var.name
  project            = var.project
  region             = var.region
  github             = var.github
  depends_on         = [module.network]
  github_environment = var.github_environment
  repository_ids     = { for service, id in module.gar.repository_ids : service => id if contains(["frontend", "backend"], service) }
}
