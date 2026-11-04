variable "name" { type = string }
variable "project" {
  type = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project))
    error_message = "gcp_project is required for GCP."
  }
}
variable "region" { type = string }
variable "admin_cidrs" {
  type        = list(string)
  description = "Trusted administrator/runner source IPv4 CIDRs as seen by the selected Kubernetes API endpoint."
  validation {
    condition     = length(var.admin_cidrs) > 0 && alltrue([for cidr in var.admin_cidrs : can(cidrnetmask(cidr)) && try(tonumber(split("/", cidr)[1]) >= 24, false)])
    error_message = "Supply trusted IPv4 administrator/runner CIDRs of /24 or narrower."
  }
  validation {
    condition     = !var.public_cluster_endpoint || alltrue([for cidr in var.admin_cidrs : !can(regex("^(0[.]|10[.]|127[.]|169[.]254[.]|172[.](1[6-9]|2[0-9]|3[01])[.]|192[.]168[.])", cidrhost(cidr, 0)))])
    error_message = "Public API allowlists require public source CIDRs; private CIDRs require private endpoint routing."
  }
}
variable "ha" { type = bool }
variable "deletion_protection" { type = bool }

variable "network_cidrs" {
  type = object({
    nodes    = optional(string, "10.50.0.0/20")
    pods     = optional(string, "10.60.0.0/16")
    services = optional(string, "10.70.0.0/20")
    master   = optional(string, "172.16.0.0/28")
    sql      = optional(string, "10.80.0.0/16")
  })
  default = {}
  validation {
    condition = alltrue([for cidr in values(var.network_cidrs) : can(cidrnetmask(cidr))]) && try(
      tonumber(split("/", var.network_cidrs.master)[1]) == 28 && tonumber(split("/", var.network_cidrs.sql)[1]) == 16, false
    )
    error_message = "Supply IPv4 CIDRs; master must be /28 and SQL /16."
  }
  validation {
    condition = alltrue(flatten([for a in values(var.network_cidrs) : [for b in values(var.network_cidrs) :
      a == b ? false : try(cidrhost("${split("/", a)[0]}/${min(tonumber(split("/", a)[1]), tonumber(split("/", b)[1]))}", 0) != cidrhost("${split("/", b)[0]}/${min(tonumber(split("/", a)[1]), tonumber(split("/", b)[1]))}", 0), false)
      if a != b
    ]])) && length(distinct(values(var.network_cidrs))) == 5
    error_message = "Node, pod, service, control-plane and SQL ranges must not overlap."
  }
}


variable "database_tier" {
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



variable "flow_logs_enabled" { type = bool }
variable "labels" { type = map(string) }

variable "public_cluster_endpoint" {
  type        = bool
  default     = false
  description = "Explicit opt-in to a CIDR-restricted public control plane; default requires private runner connectivity."
}

variable "additional_gar_services" {
  type    = set(string)
  default = []
}
variable "gar_cleanup_dry_run" {
  type    = bool
  default = true
}
variable "github_environment" { type = string }
variable "github" {
  type = object({
    repository     = string
    repository_id  = string
    owner_id       = string
    subject_prefix = optional(string)
    branch         = optional(string, "main")
  })
  default = null
}
variable "database_flags" {
  type    = map(string)
  default = {}
  validation {
    condition     = alltrue([for name, value in var.database_flags : can(regex("^[a-z][a-z0-9_.]{0,62}$", name)) && try(length(value) > 0 && length(value) <= 256, false)])
    error_message = "Supply valid Cloud SQL flag names and nonempty values up to 256 characters."
  }
}
