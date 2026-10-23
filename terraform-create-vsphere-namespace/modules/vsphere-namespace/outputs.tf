output "namespace_name" {
  value = vsphere_namespace.namespace.name
}

output "namespace_id" {
  value = vsphere_namespace.namespace.id
}

output "supervisor_id" {
  value = vsphere_namespace.namespace.supervisor
}

output "storage_policy_ids" {
  value = vsphere_namespace.namespace.storage_policies
}
