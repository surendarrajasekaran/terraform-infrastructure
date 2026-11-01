provider "aws" {
  region              = var.region
  allowed_account_ids = var.aws_account_id == null ? null : [var.aws_account_id]
  default_tags { tags = local.labels }
  ignore_tags { key_prefixes = ["QSConfigId-"] }
}
locals {
  name   = "${var.name}-${var.environment}"
  ha     = var.environment == "production"
  labels = merge(var.labels, { project = var.name, environment = var.environment, managed_by = "terraform" })
}
module "aws" {
  count                      = 1
  source                     = "../../../modules/aws"
  name                       = local.name
  public_cluster_endpoint    = var.public_cluster_endpoint
  admin_cidrs                = var.admin_cidrs
  ha                         = local.ha
  kubernetes_version         = var.kubernetes_version
  deletion_protection        = var.deletion_protection
  network_cidr               = var.aws_network_cidr
  availability_zones         = var.aws_availability_zones
  node_pool                  = var.aws_node_pool
  database_instance_class    = var.aws_database_instance_class
  database                   = var.database
  administrator_arns         = var.aws_administrator_arns
  enable_ssm_access          = var.aws_enable_ssm_access
  additional_ecr_services    = var.aws_additional_ecr_services
  github_repository          = var.github_repository
  github_oidc_provider_arn   = var.github_oidc_provider_arn
  github_oidc_subject_prefix = var.github_oidc_subject_prefix
  github_environment         = "aws-${var.environment}"
  flow_logs_enabled          = var.flow_logs_enabled
  log_retention_days         = var.log_retention_days
}


data "aws_eks_cluster" "this" {
  name = module.aws[0].cluster_name
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster.this.name, "--region", var.region]
    }
  }
}

module "argocd" {
  source        = "../../../modules/aws/argocd"
  chart_version = var.argocd_chart_version
  values        = [file("${path.module}/argocd-values.yaml")]
}
