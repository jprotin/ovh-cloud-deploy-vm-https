# -------------------------------------------------------
# Réseau privé
# -------------------------------------------------------
resource "openstack_networking_network_v2" "private_net" {
  name           = "${var.project_name}-network"
  admin_state_up = true
  region         = var.os_region
}

resource "openstack_networking_subnet_v2" "private_subnet" {
  name            = "${var.project_name}-subnet"
  network_id      = openstack_networking_network_v2.private_net.id
  cidr            = "10.0.1.0/24"
  ip_version      = 4
  dns_nameservers = ["213.186.33.99", "8.8.8.8"]
  region          = var.os_region
}

# -------------------------------------------------------
# Ext-Net
# -------------------------------------------------------
data "openstack_networking_network_v2" "ext_net" {
  network_id = "581fad02-158d-4dc6-81f0-c1ec2794bbec"
  region     = var.os_region
}

# -------------------------------------------------------
# Routeur
# -------------------------------------------------------
resource "openstack_networking_router_v2" "router" {
  name                = "${var.project_name}-router"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.ext_net.id
  region              = var.os_region
  # enable_snat supprimé — non autorisé sur OVHcloud Public Cloud
}

resource "openstack_networking_router_interface_v2" "router_iface" {
  router_id = openstack_networking_router_v2.router.id
  subnet_id = openstack_networking_subnet_v2.private_subnet.id
  region    = var.os_region
}

# -------------------------------------------------------
# Security Group
# -------------------------------------------------------
resource "openstack_networking_secgroup_v2" "sg_base" {
  name        = "${var.project_name}-sg"
  description = "Security group de base - Landing Zone"
  region      = var.os_region
}

resource "openstack_networking_secgroup_rule_v2" "ssh_in" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.admin_cidr
  security_group_id = openstack_networking_secgroup_v2.sg_base.id
  region            = var.os_region
}

resource "openstack_networking_secgroup_rule_v2" "icmp_in" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.sg_base.id
  region            = var.os_region
}

resource "openstack_networking_secgroup_rule_v2" "http_in" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.sg_base.id
  region            = var.os_region
}

resource "openstack_networking_secgroup_rule_v2" "https_in" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.sg_base.id
  region            = var.os_region
}

# -------------------------------------------------------
# Keypair SSH
# -------------------------------------------------------
resource "openstack_compute_keypair_v2" "keypair" {
  name       = "${var.project_name}-keypair"
  public_key = var.ssh_public_key
  region     = var.os_region
}

# -------------------------------------------------------
# Data sources
# -------------------------------------------------------
data "openstack_images_image_v2" "ubuntu" {
  name        = "Ubuntu 24.04"
  most_recent = true
  region      = var.os_region
}

data "openstack_compute_flavor_v2" "flavor" {
  name   = "d2-2"
  region = var.os_region
}

# -------------------------------------------------------
# IP flottante
# -------------------------------------------------------
resource "openstack_networking_floatingip_v2" "floating_ip" {
  pool   = "Ext-Net"
  region = var.os_region
}

# -------------------------------------------------------
# Port VM
# -------------------------------------------------------
resource "openstack_networking_port_v2" "vm_port" {
  name               = "${var.project_name}-port"
  network_id         = openstack_networking_network_v2.private_net.id
  admin_state_up     = true
  security_group_ids = [openstack_networking_secgroup_v2.sg_base.id]
  region             = var.os_region

  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.private_subnet.id
  }
}

# -------------------------------------------------------
# Instance VM
# -------------------------------------------------------
resource "openstack_compute_instance_v2" "vm" {
  name      = "${var.project_name}-vm"
  image_id  = data.openstack_images_image_v2.ubuntu.id
  flavor_id = data.openstack_compute_flavor_v2.flavor.id
  key_pair  = openstack_compute_keypair_v2.keypair.name
  region    = var.os_region
  user_data = file("cloud-init.yaml")

  network {
    port = openstack_networking_port_v2.vm_port.id
  }

  metadata = {
    project     = var.project_name
    environment = "sandbox"
    managed_by  = "terraform"
  }
}

# -------------------------------------------------------
# Association IP flottante <-> VM
# -------------------------------------------------------
resource "openstack_networking_floatingip_associate_v2" "fip_assoc" {
  floating_ip = openstack_networking_floatingip_v2.floating_ip.address
  port_id     = openstack_networking_port_v2.vm_port.id
  region      = var.os_region

  depends_on = [
    openstack_networking_router_interface_v2.router_iface,
    openstack_compute_instance_v2.vm
  ]
}