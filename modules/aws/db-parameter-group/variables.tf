variable "name" {
  type        = string
  description = "Resource prefix for the custom parameter group."
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,39}$", var.name))
    error_message = "Use a 3-40 character lowercase resource prefix, starting with a letter."
  }
}

variable "family" {
  type        = string
  description = "RDS parameter family compatible with the database engine major version."
}

variable "parameters" {
  type = map(object({
    value        = string
    apply_method = optional(string, "pending-reboot")
  }))
  default     = {}
  description = "Engine-specific parameter values and their application method."
  validation {
    condition = alltrue([
      for name, parameter in var.parameters :
      can(regex("^[a-z][a-z0-9_.]*$", name)) && parameter.value != null &&
      contains(["immediate", "pending-reboot"], parameter.apply_method)
    ])
    error_message = "Use valid parameter names, non-null values and immediate or pending-reboot application."
  }
}
