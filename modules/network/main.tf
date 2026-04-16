# -------------------------------------------------------
# Réseau privé (toujours créé)
# -------------------------------------------------------
resource "openstack_networking_network_v2" "this" {
  name           = "${var.project_name}-network"
  admin_state_up = true
  region         = var.region
}

resource "openstack_networking_subnet_v2" "this" {
  name            = "${var.project_name}-subnet"
  network_id      = openstack_networking_network_v2.this.id
  cidr            = var.subnet_cidr
  ip_version      = 4
  dns_nameservers = var.dns_nameservers
  region          = var.region
}

# -------------------------------------------------------
# Routeur (optionnel, pour accès Internet depuis VM)
# -------------------------------------------------------
resource "openstack_networking_router_v2" "this" {
  count = var.enable_router ? 1 : 0

  name                = "${var.project_name}-router"
  admin_state_up      = true
  external_network_id = var.ext_net_id
  region              = var.region
}

resource "openstack_networking_router_interface_v2" "this" {
  count = var.enable_router ? 1 : 0

  router_id = openstack_networking_router_v2.this[0].id
  subnet_id = openstack_networking_subnet_v2.this.id
  region    = var.region
}

# -------------------------------------------------------
# Security Group (optionnel, pour filtrage VM)
# -------------------------------------------------------
resource "openstack_networking_secgroup_v2" "this" {
  count = var.enable_secgroup ? 1 : 0

  name        = "${var.project_name}-sg"
  description = "Security group de base"
  region      = var.region
}

resource "openstack_networking_secgroup_rule_v2" "ssh_in" {
  count = var.enable_secgroup ? 1 : 0

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.admin_cidr
  security_group_id = openstack_networking_secgroup_v2.this[0].id
  region            = var.region
}

#tfsec:ignore:openstack-networking-no-public-ingress ICMP public accepté (ping, diagnostic réseau)
resource "openstack_networking_secgroup_rule_v2" "icmp_in" {
  count = var.enable_secgroup ? 1 : 0

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.this[0].id
  region            = var.region
}

#tfsec:ignore:openstack-networking-no-public-ingress HTTP public (serveur web)
resource "openstack_networking_secgroup_rule_v2" "http_in" {
  count = var.enable_secgroup ? 1 : 0

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.this[0].id
  region            = var.region
}

#tfsec:ignore:openstack-networking-no-public-ingress HTTPS public (serveur web)
resource "openstack_networking_secgroup_rule_v2" "https_in" {
  count = var.enable_secgroup ? 1 : 0

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.this[0].id
  region            = var.region
}

# -------------------------------------------------------
# Keypair SSH (optionnelle, pour VM)
# -------------------------------------------------------
resource "openstack_compute_keypair_v2" "this" {
  count = var.enable_keypair ? 1 : 0

  name       = "${var.project_name}-keypair"
  public_key = var.ssh_public_key
  region     = var.region
}
