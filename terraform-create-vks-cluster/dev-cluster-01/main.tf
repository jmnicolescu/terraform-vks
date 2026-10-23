terraform {
  required_version = ">= 1.5.0"
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
  }
}

provider "kubernetes" {
  alias          = "supervisor"
  config_path    = pathexpand(var.kubeconfig_path)
  config_context = var.supervisor_context
}

variable "kubeconfig_path" {
  description = "Path to an authenticated Supervisor kubeconfig."
  type        = string
  default     = "~/.kube/config"
}

variable "supervisor_context" {
  description = "Explicit Supervisor context, matching SUPERVISOR_CONTEXT in 00-vcf9-env.sh."
  type        = string
  default     = "supervisor"
}

module "vks_cluster" {
  source = "../modules/vks-cluster"

  providers = {
    kubernetes = kubernetes.supervisor
  }

  cluster_name               = "dev-cluster-01"
  namespace                  = "dev-namespace"
  kubernetes_version         = "v1.35.6---vmware.2-vkr.3"
  cluster_class              = "builtin-generic-v3.7.0"
  cluster_class_namespace    = "vmware-system-vks-public"
  vm_class                   = "best-effort-medium"
  storage_class              = "vsan-default-storage-policy"
  control_plane_count        = 3
  worker_count               = 3
  containerd_volume_capacity = "30Gi"
  pod_cidrs                  = ["10.95.0.0/16"]
  service_cidrs              = ["10.96.0.0/12"]
  additional_trusted_cas     = []
  
  # additional_trusted_cas = [{
  #   secret_name = "harbor-user-trusted-ca-secret"
  #   key         = "harbor-ca"
  # }]
}

output "cluster_name" {
  value = module.vks_cluster.cluster_name
}

output "namespace" {
  value = module.vks_cluster.namespace
}

output "manifest_yaml" {
  description = "Reusable Cluster YAML generated from the desired manifest."
  value       = yamlencode(module.vks_cluster.manifest)
}

resource "local_file" "cluster_manifest" {
  content              = yamlencode(module.vks_cluster.manifest)
  filename             = "${path.root}/output-${formatdate("YYYY-MM-DD", plantimestamp())}/create-dev-cluster-01.yaml"
  file_permission      = "0600"
  directory_permission = "0700"
}

output "manifest_file" {
  description = "Path to the reusable Cluster YAML, dated in UTC when the plan was created."
  value       = local_file.cluster_manifest.filename
}
