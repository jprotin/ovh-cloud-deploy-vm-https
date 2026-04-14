output "project_name" {
  description = "Nom logique du projet (pour infra.sh)"
  value       = var.project_name
}

output "enabled_modules" {
  description = "Liste des modules activés"
  value = compact([
    var.enable_vm ? "vm" : "",
    var.enable_mks ? "mks" : "",
    var.enable_dbaas ? "dbaas" : "",
  ])
}

# -------------------------------------------------------
# Outputs VM (null si enable_vm = false)
# -------------------------------------------------------
output "vm_name" {
  description = "Nom de la VM (null si VM désactivée)"
  value       = var.enable_vm ? module.vm[0].vm_name : null
}

output "vm_public_ip" {
  description = "IP publique de la VM (null si VM désactivée)"
  value       = var.enable_vm ? module.vm[0].public_ip : null
}

output "vm_private_ip" {
  description = "IP privée de la VM (null si VM désactivée)"
  value       = var.enable_vm ? module.vm[0].private_ip : null
}

output "ssh_command" {
  description = "Commande SSH vers la VM (null si VM désactivée)"
  value       = var.enable_vm ? "ssh ubuntu@${module.vm[0].public_ip}" : null
}

# -------------------------------------------------------
# Outputs MKS (null si enable_mks = false)
# -------------------------------------------------------
output "cluster_id" {
  description = "ID du cluster MKS (null si MKS désactivé)"
  value       = var.enable_mks ? module.mks[0].cluster_id : null
}

output "cluster_name" {
  description = "Nom du cluster MKS (null si MKS désactivé)"
  value       = var.enable_mks ? module.mks[0].cluster_name : null
}

output "cluster_endpoint" {
  description = "URL de l'API Kubernetes (null si MKS désactivé)"
  value       = var.enable_mks ? module.mks[0].endpoint : null
}

output "kube_version" {
  description = "Version Kubernetes (null si MKS désactivé)"
  value       = var.enable_mks ? module.mks[0].version : null
}

output "az_count" {
  description = "Nombre d'AZ MKS (null si MKS désactivé)"
  value       = var.enable_mks ? module.mks[0].az_count : null
}

output "nodepool" {
  description = "Node pool MKS (null si MKS désactivé)"
  value       = var.enable_mks ? module.mks[0].nodepool : null
}

output "total_nodes" {
  description = "Nombre total de workers MKS (null si MKS désactivé)"
  value       = var.enable_mks ? module.mks[0].total_nodes : null
}

output "kubeconfig_path" {
  description = "Chemin local du kubeconfig (null si MKS désactivé)"
  value       = var.enable_mks ? local_file.kubeconfig[0].filename : null
}

output "kubectl_command" {
  description = "Commande pour utiliser kubectl (null si MKS désactivé)"
  value       = var.enable_mks ? "export KUBECONFIG=${abspath("${path.module}/kubeconfig.yaml")}" : null
}
