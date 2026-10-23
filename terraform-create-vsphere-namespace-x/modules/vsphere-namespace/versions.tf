terraform {
  required_version = ">= 1.5.0"
  required_providers {
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
