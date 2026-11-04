resource "random_password" "database" {
  length  = 32
  special = false
}
resource "google_sql_database_instance" "ideas" {
  project             = var.project
  name                = var.name
  region              = var.region
  database_version    = "POSTGRES_16"
  deletion_protection = var.deletion_protection
  lifecycle { ignore_changes = [settings[0].disk_size] }
  settings {
    tier                  = coalesce(var.tier, var.database.high_availability ? "db-custom-2-7680" : "db-custom-1-3840")
    edition               = "ENTERPRISE"
    availability_type     = var.database.high_availability ? "REGIONAL" : "ZONAL"
    disk_type             = "PD_SSD"
    disk_size             = var.database.storage_gb
    disk_autoresize       = true
    disk_autoresize_limit = var.database.max_storage_gb
    user_labels           = var.labels
    dynamic "database_flags" {
      for_each = var.database_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
    maintenance_window {
      day          = 7
      hour         = 4
      update_track = "stable"
    }
    deletion_protection_enabled = var.deletion_protection
    retain_backups_on_delete    = true
    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      start_time                     = "02:00"
      backup_retention_settings {
        retained_backups = max(var.database.backup_days, var.database.high_availability ? 14 : 7)
        retention_unit   = "COUNT"
      }
    }
    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
      ssl_mode        = "ENCRYPTED_ONLY"
      server_ca_mode  = "GOOGLE_MANAGED_INTERNAL_CA"
    }
  }
}
resource "google_sql_database" "ideas" {
  project  = var.project
  name     = var.database.name
  instance = google_sql_database_instance.ideas.name
}
resource "google_sql_user" "ideas" {
  project  = var.project
  name     = "ideas"
  instance = google_sql_database_instance.ideas.name
  password = random_password.database.result
}

resource "random_password" "application" {
  length  = 32
  special = false
}
