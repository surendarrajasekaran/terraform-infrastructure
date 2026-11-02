output "database_url" {
  sensitive = true
  value     = "postgresql+psycopg://ideas_app:${random_password.application.result}@${aws_db_instance.ideas.address}:5432/${var.database.name}?sslmode=verify-full&sslrootcert=/etc/postgresql/ca/ca.crt"
}
output "migration_database_url" {
  sensitive = true
  value     = "postgresql+psycopg://ideas:${random_password.database.result}@${aws_db_instance.ideas.address}:5432/${var.database.name}?sslmode=verify-full&sslrootcert=/etc/postgresql/ca/ca.crt"
}
output "application_password" {
  sensitive = true
  value     = random_password.application.result
}
output "database_host" { value = aws_db_instance.ideas.address }

output "database_configuration" {
  description = "Non-secret availability, storage and parameter-group settings."
  value = {
    multi_az                    = aws_db_instance.ideas.multi_az
    allocated_storage_gb        = aws_db_instance.ideas.allocated_storage
    max_allocated_storage_gb    = aws_db_instance.ideas.max_allocated_storage
    storage_autoscaling_enabled = aws_db_instance.ideas.max_allocated_storage > 0
    parameter_group_name        = aws_db_instance.ideas.parameter_group_name
  }
}

output "database_ca_certificate" {
  sensitive = true
  value     = ""
} # RDS global trust bundle is obtained over HTTPS by the deployer.
