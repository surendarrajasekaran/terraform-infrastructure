output "database_url" {
  sensitive = true
  value     = "postgresql+psycopg://ideas_app:${random_password.application.result}@${google_sql_database_instance.ideas.private_ip_address}:5432/${var.database.name}?sslmode=verify-ca&sslrootcert=/etc/postgresql/ca/ca.crt"
}
output "migration_database_url" {
  sensitive = true
  value     = "postgresql+psycopg://ideas:${random_password.database.result}@${google_sql_database_instance.ideas.private_ip_address}:5432/${var.database.name}?sslmode=verify-ca&sslrootcert=/etc/postgresql/ca/ca.crt"
}
output "application_password" {
  sensitive = true
  value     = random_password.application.result
}
output "database_host" { value = google_sql_database_instance.ideas.private_ip_address }

output "database_ca_certificate" {
  sensitive = true
  value     = google_sql_database_instance.ideas.server_ca_cert[0].cert
}

output "database_configuration" {
  value = {
    availability_type           = google_sql_database_instance.ideas.settings[0].availability_type
    allocated_storage_gb        = google_sql_database_instance.ideas.settings[0].disk_size
    max_storage_gb              = google_sql_database_instance.ideas.settings[0].disk_autoresize_limit
    storage_autoscaling_enabled = google_sql_database_instance.ideas.settings[0].disk_autoresize
    ssl_mode                    = google_sql_database_instance.ideas.settings[0].ip_configuration[0].ssl_mode
    database_flags              = var.database_flags
    retain_backups_on_delete    = google_sql_database_instance.ideas.settings[0].retain_backups_on_delete
  }
}
