data "vsphere_datacenter" "target" {
  name = var.datacenter_name
}

data "vsphere_compute_cluster" "target" {
  name          = var.cluster_name
  datacenter_id = data.vsphere_datacenter.target.id
}

data "vsphere_storage_policy" "namespace" {
  for_each = toset(var.storage_policy_names)
  name     = each.value
}

data "vsphere_content_library" "namespace" {
  for_each = toset(var.content_library_names)
  name     = each.value
}

locals {
  settings = {
    description = var.description
    storage_specs = [for name in sort(var.storage_policy_names) : {
      policy = data.vsphere_storage_policy.namespace[name].id
      limit  = var.storage_limit_mib
    }]
    vm_service_spec = {
      vm_classes        = sort(var.vm_classes)
      content_libraries = [for name in sort(var.content_library_names) : data.vsphere_content_library.namespace[name].id]
    }
  }
  create_spec = merge(local.settings, {
    cluster   = data.vsphere_compute_cluster.target.id
    namespace = var.namespace_name
  })
}

resource "restapi_object" "namespace" {
  path           = "/api/vcenter/namespaces/instances"
  object_id      = var.namespace_name
  id_attribute   = "namespace"
  create_method  = "POST"
  read_method    = "GET"
  update_method  = "PATCH"
  destroy_method = "DELETE"
  data           = jsonencode(local.create_spec)
  update_data    = jsonencode(local.settings)
  force_new      = ["namespace", "cluster"]
}
