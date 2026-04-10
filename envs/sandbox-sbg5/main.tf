# -------------------------------------------------------
# Ext-Net (réseau externe OVHcloud)
# -------------------------------------------------------
data "openstack_networking_network_v2" "ext_net" {
  network_id = "581fad02-158d-4dc6-81f0-c1ec2794bbec"
  region     = var.os_region
}

# -------------------------------------------------------
# Module réseau
# -------------------------------------------------------
module "network" {
  source = "../../modules/network"

  project_name   = var.project_name
  region         = var.os_region
  subnet_cidr    = "10.0.1.0/24"
  admin_cidr     = var.admin_cidr
  ssh_public_key = var.ssh_public_key
  ext_net_id     = data.openstack_networking_network_v2.ext_net.id
}

# -------------------------------------------------------
# Module compute (VM)
# -------------------------------------------------------
module "vm" {
  source = "../../modules/compute"

  project_name = var.project_name
  region       = var.os_region
  network_id   = module.network.network_id
  subnet_id    = module.network.subnet_id
  secgroup_id  = module.network.secgroup_id
  keypair_name = module.network.keypair_name
  image_name   = "Ubuntu 24.04"
  flavor_name  = "d2-2"
  user_data    = file("${path.module}/cloud-init.yaml")

  metadata = {
    project     = var.project_name
    environment = "sandbox"
    managed_by  = "terraform"
  }

  depends_on = [module.network]
}
