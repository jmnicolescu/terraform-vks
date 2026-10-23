terraform {
  required_version = ">= 1.10.0"
  required_providers {
    restful = {
      source  = "magodo/restful"
      version = "~> 0.25.2"
    }
    vsphere = {
      source  = "vmware/vsphere"
      version = "~> 2.16"
    }
    restapi = {
      source  = "Mastercard/restapi"
      version = "~> 2.0"
    }
  }
}

provider "vsphere" {
  vsphere_server       = var.vcenter
  user                 = var.vcenter_user
  password             = var.vcenter_password
  allow_unverified_ssl = var.insecure_tls
}

provider "restapi" {
  uri                  = "https://${var.vcenter}"
  insecure             = var.insecure_tls
  timeout              = 120
  write_returns_object = false
  debug                = false
  headers = {
    "vmware-api-session-id" = ephemeral.restful_resource.vcenter_session.sensitive_output
    "Content-Type"          = "application/json"
  }
}

module "vsphere_namespace" {
  source = "../modules/vsphere-namespace"

  namespace_name        = "dev-namespace"
  description           = "Dev Namespace"
  datacenter_name       = "platformlab-dc01"
  cluster_name          = "platformlab-cl01"
  storage_policy_names  = ["vSAN Default Storage Policy"]
  storage_limit_mib     = 512000
  content_library_names = ["vkr-content-library"]
  vm_classes            = ["best-effort-small", "best-effort-medium", "best-effort-large", "best-effort-xlarge"]
}

output "namespace_name" {
  value = module.vsphere_namespace.namespace_name
}

output "config_status" {
  value = module.vsphere_namespace.config_status
}

output "create_spec" {
  value = module.vsphere_namespace.create_spec
}
