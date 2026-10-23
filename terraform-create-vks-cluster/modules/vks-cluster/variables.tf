variable "cluster_name" {
  description = "Name of the VKS Cluster."
  type        = string
  nullable    = false
  validation {
    condition     = length(trimspace(var.cluster_name)) > 0
    error_message = "Value must not be empty."
  }
}

variable "namespace" {
  description = "Existing Supervisor namespace."
  type        = string
  nullable    = false
  validation {
    condition     = length(trimspace(var.namespace)) > 0
    error_message = "Value must not be empty."
  }
}

variable "kubernetes_version" {
  description = "Exact VKS release identifier supported by the Supervisor."
  type        = string
  nullable    = false
  validation {
    condition     = length(trimspace(var.kubernetes_version)) > 0
    error_message = "Value must not be empty."
  }
}

variable "cluster_class" {
  description = "Existing ClusterClass name."
  type        = string
  nullable    = false
  validation {
    condition     = length(trimspace(var.cluster_class)) > 0
    error_message = "Value must not be empty."
  }
}

variable "cluster_class_namespace" {
  description = "Namespace containing the ClusterClass."
  type        = string
  default     = "vmware-system-vks-public"
  nullable    = false
  validation {
    condition     = length(trimspace(var.cluster_class_namespace)) > 0
    error_message = "Value must not be empty."
  }
}

variable "vm_class" {
  description = "VM class assigned to the Supervisor namespace."
  type        = string
  nullable    = false
  validation {
    condition     = length(trimspace(var.vm_class)) > 0
    error_message = "Value must not be empty."
  }
}

variable "storage_class" {
  description = "Storage class for nodes and the containerd volume."
  type        = string
  nullable    = false
  validation {
    condition     = length(trimspace(var.storage_class)) > 0
    error_message = "Value must not be empty."
  }
}

variable "containerd_volume_capacity" {
  description = "Capacity of each worker's containerd volume as a Kubernetes quantity, for example 30Gi."
  type        = string
  default     = "30Gi"
  nullable    = false
  validation {
    condition     = length(trimspace(var.containerd_volume_capacity)) > 0
    error_message = "Supply a nonempty volume capacity, for example 30Gi."
  }
}

variable "control_plane_count" {
  description = "Number of control-plane nodes."
  type        = number
  default     = 3
  nullable    = false
  validation {
    condition     = var.control_plane_count >= 1 && floor(var.control_plane_count) == var.control_plane_count
    error_message = "Use a positive integer supported by the ClusterClass."
  }
}

variable "worker_count" {
  description = "Number of nodes in the single worker pool."
  type        = number
  default     = 3
  nullable    = false
  validation {
    condition     = var.worker_count >= 0 && floor(var.worker_count) == var.worker_count
    error_message = "Use a nonnegative integer supported by the ClusterClass."
  }
}

variable "pod_cidrs" {
  description = "Pod network CIDRs."
  type        = list(string)
  nullable    = false
  validation {
    condition     = length(var.pod_cidrs) > 0 && alltrue([for cidr in var.pod_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Supply at least one valid CIDR."
  }
}

variable "service_cidrs" {
  description = "Service network CIDRs."
  type        = list(string)
  nullable    = false
  validation {
    condition     = length(var.service_cidrs) > 0 && alltrue([for cidr in var.service_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Supply at least one valid CIDR."
  }
}

variable "additional_trusted_cas" {
  description = "Existing CA Secret references in the cluster namespace; empty disables additional trust."
  type        = list(object({ secret_name = string, key = string }))
  default     = []
  nullable    = false
  validation {
    condition     = alltrue([for ca in var.additional_trusted_cas : length(trimspace(ca.secret_name)) > 0 && length(trimspace(ca.key)) > 0])
    error_message = "Each CA reference needs a Secret name and key."
  }
}

