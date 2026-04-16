# -------------------------------------------------------
# Réseau privé + subnet (requis pour MKS en région 3AZ)
# Mode minimal : pas de routeur, secgroup, ni keypair (MKS n'en a pas besoin)
# -------------------------------------------------------
module "network" {
  source = "../../modules/network"

  project_name = var.project_name
  region       = var.region

  # Features désactivées : MKS se charge de tout
  enable_router   = false
  enable_secgroup = false
  enable_keypair  = false

  subnet_cidr = var.subnet_cidr
}

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

  # Réseau privé + subnet requis en région 3AZ
  private_network_id = module.network.network_id
  nodes_subnet_id    = module.network.subnet_id
}

# -------------------------------------------------------
# Kubeconfig local (gitignoré)
# -------------------------------------------------------
resource "local_file" "kubeconfig" {
  content         = module.mks.kubeconfig
  filename        = "${path.module}/kubeconfig.yaml"
  file_permission = "0600"
}
