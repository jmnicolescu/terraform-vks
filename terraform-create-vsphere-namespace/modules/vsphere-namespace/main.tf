data "restful_resource" "supervisors" {
  id     = "/api/vcenter/namespace-management/supervisors/summaries"
  method = "GET"

  lifecycle {
    postcondition {
      condition = try(length([
        for item in self.output.items : item
        if item.info.name == var.supervisor_name
      ]) == 1, false)
      error_message = "Supervisor discovery must return exactly one match for the configured supervisor_name."
    }
    postcondition {
      condition = try(can(regex(
        "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
        one([for item in self.output.items : item.supervisor if item.info.name == var.supervisor_name])
      )), false)
      error_message = "Supervisor discovery did not return a valid UUID for the configured name."
    }
  }
}

locals {
  supervisor_id = try(one([
    for item in data.restful_resource.supervisors.output.items : item.supervisor
    if item.info.name == var.supervisor_name
  ]), "")
}

data "vsphere_storage_policy" "namespace" {
  for_each = toset(var.storage_policy_names)
  name     = each.value
}

data "vsphere_content_library" "namespace" {
  for_each = toset(var.content_library_names)
  name     = each.value
}

resource "vsphere_namespace" "namespace" {
  name             = var.namespace_name
  supervisor       = local.supervisor_id
  storage_policies = [for name in sort(var.storage_policy_names) : data.vsphere_storage_policy.namespace[name].id]

  vm_service {
    content_libraries = [for name in sort(var.content_library_names) : data.vsphere_content_library.namespace[name].id]
    vm_classes        = sort(var.vm_classes)
  }
}
