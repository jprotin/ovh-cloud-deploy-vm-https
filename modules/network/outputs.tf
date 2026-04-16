output "network_id" {
  description = "ID du réseau privé"
  value       = openstack_networking_network_v2.this.id
}

output "subnet_id" {
  description = "ID du subnet"
  value       = openstack_networking_subnet_v2.this.id
}

output "secgroup_id" {
  description = "ID du security group (null si enable_secgroup = false)"
  value       = var.enable_secgroup ? openstack_networking_secgroup_v2.this[0].id : null
}

output "keypair_name" {
  description = "Nom de la keypair SSH (null si enable_keypair = false)"
  value       = var.enable_keypair ? openstack_compute_keypair_v2.this[0].name : null
}

output "router_id" {
  description = "ID du routeur (null si enable_router = false)"
  value       = var.enable_router ? openstack_networking_router_v2.this[0].id : null
}
