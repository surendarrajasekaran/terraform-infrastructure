cloud                       = "aws"
name                        = "idea-board"
environment                 = "test"
region                      = "us-west-2"
aws_account_id              = "812752207041"
admin_cidrs                 = ["206.206.99.46/32"]
public_cluster_endpoint     = true
aws_enable_ssm_access       = true
aws_node_pool               = { min_size = 2, desired_size = 2, max_size = 3, instance_types = ["t3.medium"], disk_size = 20 }
aws_database_instance_class = "db.t3.micro"
kubernetes_version          = "1.35"
github_repository           = "surendarrajasekaran/om-idea-board"
github_oidc_provider_arn    = "arn:aws:iam::812752207041:oidc-provider/token.actions.githubusercontent.com"
labels                      = { owner = "surendar", cost_center = "case-study" }

aws_additional_ecr_services = ["argocd"]

github_oidc_subject_prefix = "repo:surendarrajasekaran@35868093/om-idea-board@1438722777"
argocd_chart_version       = "10.11.6"

database = {
  multi_az           = true
  storage_gb         = 20
  max_storage_gb     = 100
  backup_days        = 14
  log_retention_days = 14
}
