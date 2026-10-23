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
