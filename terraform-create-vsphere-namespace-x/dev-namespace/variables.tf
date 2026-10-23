variable "vcenter" {
  description = "vCenter hostname from VCENTER in 00-vcf9-env.sh."
  type        = string
  default     = "mgmt-vcsa.platformlab.vcf"
}

variable "vcenter_user" {
  description = "vCenter account for inventory discovery and automatic session login."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "vcenter_password" {
  description = "vCenter password for inventory discovery and automatic session login."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "insecure_tls" {
  description = "Lab TLS setting copied from VC_INSECURE; false requires trusted certificates."
  type        = bool
  default     = true
}
