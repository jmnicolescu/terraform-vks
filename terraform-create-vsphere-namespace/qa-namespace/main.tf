terraform {
  required_version = ">= 1.10.0"
  required_providers {
    restful = {
      source  = "magodo/restful"
      version = "= 0.25.2"
    }
    vsphere = {
      source  = "vmware/vsphere"
      version = "= 2.17.1"
    }
  }
}

provider "vsphere" {
  vsphere_server       = var.vcenter
  user                 = var.vcenter_user
  password             = var.vcenter_password
  allow_unverified_ssl = var.insecure_tls
}

module "vsphere_namespace" {
  source = "../modules/vsphere-namespace"

  namespace_name        = "qa-namespace"
  supervisor_name       = "lab-supervisor"
  storage_policy_names  = ["vSAN Default Storage Policy"]
  content_library_names = ["vkr-content-library"]
  vm_classes            = ["best-effort-small", "best-effort-medium", "best-effort-large", "best-effort-xlarge"]
}

output "namespace_name" {
  value = module.vsphere_namespace.namespace_name
}

output "namespace_id" {
  value = module.vsphere_namespace.namespace_id
}

output "supervisor_id" {
  value = module.vsphere_namespace.supervisor_id
}

output "storage_policy_ids" {
  value = module.vsphere_namespace.storage_policy_ids
}
