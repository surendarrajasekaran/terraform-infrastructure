variable "name" {
  type = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,39}$", var.name))
    error_message = "Use a 3-40 character lowercase resource prefix, starting with a letter."
  }
}
variable "region" { type = string }
variable "network_id" { type = string }
variable "ha" { type = bool }
variable "deletion_protection" { type = bool }
variable "labels" { type = map(string) }
variable "tier" {
  type     = string
  default  = null
  nullable = true
}
variable "database" {
  type = object({
    high_availability = optional(bool, true)
    name              = optional(string, "ideas")
    storage_gb        = optional(number, 20)
    max_storage_gb    = optional(number, 100)
    backup_days       = optional(number, 7)
  })
  default = {}
  validation {
    condition = (
      (!var.ha || var.database.high_availability) &&
      can(regex("^[a-z][a-z0-9_]{0,30}$", var.database.name)) &&
      var.database.storage_gb >= 20 && var.database.max_storage_gb >= var.database.storage_gb + min(floor(5 + var.database.storage_gb / 25), 25) &&
      var.database.backup_days >= 7 && var.database.backup_days <= 35 &&
      alltrue([for n in [var.database.storage_gb, var.database.max_storage_gb, var.database.backup_days] : n == floor(n)])
    )
    error_message = "Use a safe database name, integer storage >= 20 GiB, room for one SSD storage-autogrowth increment, backups 7-35 days and regional availability for production."
  }
}



variable "project" { type = string }
variable "database_flags" {
  type    = map(string)
  default = {}
  validation {
    condition     = alltrue([for name, value in var.database_flags : can(regex("^[a-z][a-z0-9_.]{0,62}$", name)) && try(length(value) > 0 && length(value) <= 256, false)])
    error_message = "Supply valid Cloud SQL flag names and nonempty values up to 256 characters."
  }
}
