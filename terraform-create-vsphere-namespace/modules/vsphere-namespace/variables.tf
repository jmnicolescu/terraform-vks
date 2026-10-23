variable "namespace_name" {
  description = "Namespace name. Keep identity unchanged after creation."
  type        = string
  validation {
    condition     = length(var.namespace_name) <= 63 && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.namespace_name))
    error_message = "Use a lowercase DNS label of 1 to 63 characters."
  }
}

variable "supervisor_name" {
  description = "Exact name of the existing Supervisor to discover through vCenter."
  type        = string
  validation {
    condition     = length(trimspace(var.supervisor_name)) > 0
    error_message = "Supply a nonempty Supervisor name."
  }
}

variable "storage_policy_names" {
  description = "Existing storage policies to assign. The native resource does not configure their limits."
  type        = list(string)
  validation {
    condition     = length(var.storage_policy_names) > 0 && length(distinct(var.storage_policy_names)) == length(var.storage_policy_names)
    error_message = "Provide at least one storage policy without duplicates."
  }
}

variable "content_library_names" {
  description = "Existing content libraries to bind to namespace VM Service."
  type        = list(string)
  default     = []
}

variable "vm_classes" {
  description = "Existing VM classes to bind to namespace VM Service."
  type        = list(string)
  default     = []
}
