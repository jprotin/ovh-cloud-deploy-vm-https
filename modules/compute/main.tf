# -------------------------------------------------------
# Data sources
# -------------------------------------------------------
data "openstack_images_image_v2" "this" {
  name        = var.image_name
  most_recent = true
  region      = var.region
}

data "openstack_compute_flavor_v2" "this" {
  name   = var.flavor_name
  region = var.region
}

# -------------------------------------------------------
# Port VM
# -------------------------------------------------------
resource "openstack_networking_port_v2" "this" {
  name               = "${var.project_name}-port"
  network_id         = var.network_id
  admin_state_up     = true
  security_group_ids = [var.secgroup_id]
  region             = var.region

  fixed_ip {
    subnet_id = var.subnet_id
  }
}

# -------------------------------------------------------
# IP flottante
# -------------------------------------------------------
resource "openstack_networking_floatingip_v2" "this" {
  pool   = "Ext-Net"
  region = var.region
}

# -------------------------------------------------------
# Instance VM
# -------------------------------------------------------
resource "openstack_compute_instance_v2" "this" {
  name      = "${var.project_name}-vm"
  image_id  = data.openstack_images_image_v2.this.id
  flavor_id = data.openstack_compute_flavor_v2.this.id
  key_pair  = var.keypair_name
  region    = var.region
  user_data = var.user_data

  network {
    port = openstack_networking_port_v2.this.id
  }

  metadata = var.metadata
}

# -------------------------------------------------------
# Association IP flottante <-> VM
# -------------------------------------------------------
resource "openstack_networking_floatingip_associate_v2" "this" {
  floating_ip = openstack_networking_floatingip_v2.this.address
  port_id     = openstack_networking_port_v2.this.id
  region      = var.region

  depends_on = [
    openstack_compute_instance_v2.this
  ]
}
