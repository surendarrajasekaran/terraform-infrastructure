variable "name" { type = string }
variable "project" { type = string }
variable "region" { type = string }
variable "services" {
  type = set(string)
  validation {
    condition     = length(var.services) > 0 && alltrue([for service in var.services : can(regex("^[a-z][a-z0-9-]{0,24}$", service))])
    error_message = "Supply safe lowercase service names of 1-25 characters."
  }
}
variable "node_service_account_email" { type = string }
variable "labels" { type = map(string) }
variable "cleanup_dry_run" {
  type        = bool
  default     = true
  description = "Review cleanup candidates before enabling deletion; tagged immutable releases are retained."
}
variable "untagged_retention_days" {
  type    = number
  default = 14
  validation {
    condition     = var.untagged_retention_days >= 7 && var.untagged_retention_days <= 365 && floor(var.untagged_retention_days) == var.untagged_retention_days
    error_message = "Keep untagged artifacts for an integer 7-365 days."
  }
}
