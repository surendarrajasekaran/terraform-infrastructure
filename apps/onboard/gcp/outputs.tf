output "cluster_name" {
  value = module.gcp[0].cluster_name
}
output "database_url" {
  description = "Sensitive SQLAlchemy connection URI; deliver to the common chart's existing Secret."
  sensitive   = true
  value       = module.gcp[0].database_url
}
output "cloud" { value = var.cloud }
output "repository_urls" { value = module.gcp[0].repository_urls }
output "region" { value = var.region }
output "environment" { value = var.environment }
output "gcp_project" { value = var.gcp_project }

output "name" { value = var.name }
output "migration_database_url" {
  value     = module.gcp[0].migration_database_url
  sensitive = true
}
output "application_password" {
  value     = module.gcp[0].application_password
  sensitive = true
}
output "database_host" {
  value = module.gcp[0].database_host
}

output "database_egress_cidrs" { value = module.gcp[0].database_egress_cidrs }

output "database_ca_certificate" {
  sensitive = true
  value     = module.gcp[0].database_ca_certificate
}

output "registry_host" { value = module.gcp[0].registry_host }
output "node_service_account_email" { value = module.gcp[0].node_service_account_email }
output "workload_identity_provider" { value = module.gcp[0].workload_identity_provider }
output "publisher_service_account_email" { value = module.gcp[0].publisher_service_account_email }
output "database_configuration" { value = module.gcp[0].database_configuration }
