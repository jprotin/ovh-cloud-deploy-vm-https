output "cluster_id" {
  description = "ID du cluster MKS"
  value       = ovh_cloud_project_kube.this.id
}

output "cluster_name" {
  description = "Nom du cluster MKS"
  value       = ovh_cloud_project_kube.this.name
}

output "endpoint" {
  description = "URL de l'API Kubernetes"
  value       = ovh_cloud_project_kube.this.url
}

output "version" {
  description = "Version de Kubernetes déployée"
  value       = ovh_cloud_project_kube.this.version
}

output "kubeconfig" {
  description = "Contenu du kubeconfig (à écrire en local_file côté env)"
  value       = ovh_cloud_project_kube.this.kubeconfig
  sensitive   = true
}

output "nodepool" {
  description = "Détails du node pool"
  value = {
    id            = ovh_cloud_project_kube_nodepool.this.id
    name          = ovh_cloud_project_kube_nodepool.this.name
    flavor        = ovh_cloud_project_kube_nodepool.this.flavor_name
    desired_nodes = ovh_cloud_project_kube_nodepool.this.desired_nodes
    anti_affinity = ovh_cloud_project_kube_nodepool.this.anti_affinity
  }
}

output "az_count" {
  description = "Nombre d'AZ logiques sur lesquelles le cluster est réparti"
  value       = var.az_count
}

output "total_nodes" {
  description = "Nombre total de workers dans le cluster"
  value       = var.az_count * var.nodes_per_pool
}
