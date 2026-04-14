locals {
  vm_enabled  = var.enable_vm
  mks_enabled = var.enable_mks
}

# -------------------------------------------------------
# Ext-Net (uniquement si VM)
# -------------------------------------------------------
data "openstack_networking_network_v2" "ext_net" {
  count = local.vm_enabled ? 1 : 0

  name   = "Ext-Net"
  region = var.os_region
}

# -------------------------------------------------------
# Module network (uniquement si VM)
# -------------------------------------------------------
module "network" {
  count  = local.vm_enabled ? 1 : 0
  source = "../../modules/network"

  project_name   = var.project_name
  region         = var.os_region
  subnet_cidr    = "10.0.1.0/24"
  admin_cidr     = var.admin_cidr
  ssh_public_key = var.ssh_public_key
  ext_net_id     = data.openstack_networking_network_v2.ext_net[0].id
}

# -------------------------------------------------------
# Module compute (VM)
# -------------------------------------------------------
module "vm" {
  count  = local.vm_enabled ? 1 : 0
  source = "../../modules/compute"

  project_name = var.project_name
  region       = var.os_region
  network_id   = module.network[0].network_id
  subnet_id    = module.network[0].subnet_id
  secgroup_id  = module.network[0].secgroup_id
  keypair_name = module.network[0].keypair_name
  image_name   = var.vm_image_name
  flavor_name  = var.vm_flavor
  user_data    = file("${path.module}/cloud-init.yaml")

  metadata = {
    project     = var.project_name
    environment = "sandbox"
    managed_by  = "terraform"
  }

  depends_on = [module.network]
}

# -------------------------------------------------------
# Module MKS
# -------------------------------------------------------
module "mks" {
  count  = local.mks_enabled ? 1 : 0
  source = "../../modules/mks"

  service_name = var.ovh_service_name
  cluster_name = "${var.project_name}-mks"
  region       = var.mks_region
  kube_version = var.mks_version

  az_count = var.mks_az_count

  node_flavor    = var.mks_node_flavor
  nodes_per_pool = var.mks_nodes_per_pool

  api_allowed_cidrs = var.mks_api_allowed_cidrs
}

# -------------------------------------------------------
# Kubeconfig local (gitignoré) — écrit si MKS activé
# -------------------------------------------------------
resource "local_file" "kubeconfig" {
  count = local.mks_enabled ? 1 : 0

  content         = module.mks[0].kubeconfig
  filename        = "${path.module}/kubeconfig.yaml"
  file_permission = "0600"
}

# -------------------------------------------------------
# Module DBaaS (placeholder — non implémenté)
# -------------------------------------------------------
# module "dbaas" {
#   count  = var.enable_dbaas ? 1 : 0
#   source = "../../modules/dbaas"
#   ...
# }
