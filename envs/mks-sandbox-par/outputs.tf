output "project_name" {
  description = "Nom logique du projet (pour infra.sh)"
  value       = var.project_name
}

output "cluster_id" {
  description = "ID du cluster MKS"
  value       = module.mks.cluster_id
}

output "cluster_name" {
  description = "Nom du cluster MKS"
  value       = module.mks.cluster_name
}

output "cluster_endpoint" {
  description = "URL de l'API Kubernetes"
  value       = module.mks.endpoint
}

output "kube_version" {
  description = "Version de Kubernetes déployée"
  value       = module.mks.version
}

output "az_count" {
  description = "Nombre d'AZ sur lesquelles le cluster est réparti"
  value       = module.mks.az_count
}

output "nodepool" {
  description = "Détails du node pool"
  value       = module.mks.nodepool
}

output "total_nodes" {
  description = "Nombre total de workers"
  value       = module.mks.total_nodes
}

output "kubeconfig_path" {
  description = "Chemin absolu du kubeconfig local"
  value       = abspath(local_file.kubeconfig.filename)
}

output "kubectl_command" {
  description = "Commande pour utiliser kubectl avec ce cluster"
  value       = "export KUBECONFIG=${abspath(local_file.kubeconfig.filename)}"
}
