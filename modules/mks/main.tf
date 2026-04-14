locals {
  # Nombre total de nodes = az_count × nodes_per_pool
  # En région 3AZ, OVH distribue automatiquement entre les AZ
  total_nodes = var.az_count * var.nodes_per_pool

  # Anti-affinity activé dès qu'on vise plus d'une AZ logique
  use_anti_affinity = var.az_count > 1
}

# -------------------------------------------------------
# Cluster MKS
# -------------------------------------------------------
resource "ovh_cloud_project_kube" "this" {
  service_name  = var.service_name
  name          = var.cluster_name
  region        = var.region
  version       = var.kube_version
  update_policy = var.update_policy

  # Intégration réseau privé (optionnelle)
  private_network_id = var.private_network_id
}

# -------------------------------------------------------
# IP restrictions sur l'API Kube (optionnel)
# -------------------------------------------------------
resource "ovh_cloud_project_kube_iprestrictions" "this" {
  count = length(var.api_allowed_cidrs) > 0 ? 1 : 0

  service_name = var.service_name
  kube_id      = ovh_cloud_project_kube.this.id
  ips          = var.api_allowed_cidrs
}

# -------------------------------------------------------
# Node pool
# - En région 3AZ : OVH distribue automatiquement les nodes sur les AZ disponibles
# - anti_affinity = true force la répartition sur des hyperviseurs/AZ différents
# -------------------------------------------------------
resource "ovh_cloud_project_kube_nodepool" "this" {
  service_name = var.service_name
  kube_id      = ovh_cloud_project_kube.this.id
  name         = "default-pool"

  flavor_name   = var.node_flavor
  desired_nodes = local.total_nodes
  min_nodes     = var.autoscale ? var.min_nodes_per_pool * var.az_count : local.total_nodes
  max_nodes     = var.autoscale ? var.max_nodes_per_pool * var.az_count : local.total_nodes
  autoscale     = var.autoscale

  anti_affinity = local.use_anti_affinity
}
