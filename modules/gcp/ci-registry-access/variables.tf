variable "name" { type = string }
variable "project" { type = string }
variable "region" { type = string }
variable "repository_ids" { type = map(string) }
variable "github_environment" {
  type = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,39}$", var.github_environment))
    error_message = "Use a safe lowercase GitHub environment name."
  }
}
variable "github" {
  type = object({
    repository     = string
    repository_id  = string
    owner_id       = string
    subject_prefix = optional(string)
    branch         = optional(string, "main")
  })
  validation {
    condition = (
      can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github.repository)) &&
      can(regex("^[0-9]+$", var.github.repository_id)) && can(regex("^[0-9]+$", var.github.owner_id)) &&
      can(regex("^[A-Za-z0-9_/-]+$", var.github.branch)) &&
      (var.github.subject_prefix == null || try(contains([
        "repo:${var.github.repository}",
        "repo:${split("/", var.github.repository)[0]}@${var.github.owner_id}/${split("/", var.github.repository)[1]}@${var.github.repository_id}"
      ], var.github.subject_prefix), false))
    )
    error_message = "Supply owner/repo, numeric immutable repository/owner IDs, a safe branch and an exact matching conventional or immutable-ID subject prefix."
  }
}
