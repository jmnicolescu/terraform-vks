output "namespace_name" {
  value = restapi_object.namespace.id
}

output "cluster_id" {
  value = data.vsphere_compute_cluster.target.id
}

output "create_spec" {
  description = "Desired vCenter namespace CreateSpec, containing resolved inventory IDs."
  value       = local.create_spec
}

output "config_status" {
  description = "Last observed status; only RUNNING means namespace configuration is complete."
  value       = try(jsondecode(restapi_object.namespace.api_response).config_status, "UNKNOWN")
}
