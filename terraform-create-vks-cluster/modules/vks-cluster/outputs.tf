output "cluster_name" {
  description = "Managed Cluster name; does not indicate readiness."
  value       = kubernetes_manifest.cluster.object.metadata.name
}

output "namespace" {
  description = "Supervisor namespace containing the Cluster."
  value       = kubernetes_manifest.cluster.object.metadata.namespace
}

output "manifest" {
  description = "Desired Cluster manifest, before server defaults and reconciliation."
  value       = local.cluster_manifest
}
