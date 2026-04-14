# -------------------------------------------------------
# Cluster MKS (Paris 3AZ — multi-AZ par défaut)
# -------------------------------------------------------
module "mks" {
  source = "../../modules/mks"

  service_name = var.ovh_service_name
  cluster_name = var.cluster_name
  region       = var.region
  kube_version = var.kube_version

  az_count = var.az_count

  node_flavor    = var.node_flavor
  nodes_per_pool = var.nodes_per_pool

  api_allowed_cidrs = var.api_allowed_cidrs
}

# -------------------------------------------------------
# Kubeconfig local (gitignoré)
# -------------------------------------------------------
resource "local_file" "kubeconfig" {
  content         = module.mks.kubeconfig
  filename        = "${path.module}/kubeconfig.yaml"
  file_permission = "0600"
}
