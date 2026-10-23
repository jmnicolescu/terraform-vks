variable "namespace_name" {
  description = "vSphere namespace name; changing this replaces the namespace."
  type        = string
  validation {
    condition     = length(var.namespace_name) <= 63 && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.namespace_name))
    error_message = "Use a lowercase DNS label of 1 to 63 characters."
  }
}

variable "description" {
  description = "Namespace description."
  type        = string
}

variable "datacenter_name" {
  description = "Existing datacenter used to scope the cluster lookup."
  type        = string
}

variable "cluster_name" {
  description = "Existing Supervisor-enabled cluster; changing it replaces the namespace."
  type        = string
}

variable "storage_policy_names" {
  description = "Existing storage policy names to assign."
  type        = list(string)
  validation {
    condition     = length(var.storage_policy_names) > 0 && length(distinct(var.storage_policy_names)) == length(var.storage_policy_names)
    error_message = "Provide at least one storage policy without duplicates."
  }
}

variable "storage_limit_mib" {
  description = "Storage limit in MiB for EACH assigned policy; 512000 MiB is 500 GiB."
  type        = number
  default     = 512000
  validation {
    condition     = var.storage_limit_mib >= 0 && floor(var.storage_limit_mib) == var.storage_limit_mib
    error_message = "Storage limit must be a nonnegative integer in MiB."
  }
}

variable "content_library_names" {
  description = "Existing content libraries assigned to namespace VM Service."
  type        = list(string)
  default     = []
}

variable "vm_classes" {
  description = "Existing VM class names assigned to namespace VM Service."
  type        = list(string)
  default     = []
}
