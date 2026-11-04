output "cluster_name" { value = module.kubernetes.cluster_name }
output "database_url" {
  value     = module.postgres.database_url
  sensitive = true
}
output "migration_database_url" {
  value     = module.postgres.migration_database_url
  sensitive = true
}
output "application_password" {
  value     = module.postgres.application_password
  sensitive = true
}
output "database_host" {
  value = module.postgres.database_host
}

output "database_egress_cidrs" { value = module.network.database_egress_cidrs }

output "database_ca_certificate" {
  sensitive = true
  value     = module.postgres.database_ca_certificate
}

output "repository_urls" { value = module.gar.repository_urls }
output "registry_host" { value = module.gar.registry_host }
output "node_service_account_email" { value = module.kubernetes.node_service_account_email }
output "workload_identity_provider" { value = try(module.ci_registry_access[0].workload_identity_provider, null) }
output "publisher_service_account_email" { value = try(module.ci_registry_access[0].service_account_email, null) }
output "cluster_endpoint" { value = module.kubernetes.cluster_endpoint }
output "cluster_certificate_authority_data" { value = module.kubernetes.cluster_certificate_authority_data }
output "database_configuration" { value = module.postgres.database_configuration }
