output "network_id" {
  description = "ID du réseau privé"
  value       = openstack_networking_network_v2.this.id
}

output "subnet_id" {
  description = "ID du subnet"
  value       = openstack_networking_subnet_v2.this.id
}

output "secgroup_id" {
  description = "ID du security group"
  value       = openstack_networking_secgroup_v2.this.id
}

output "keypair_name" {
  description = "Nom de la keypair SSH"
  value       = openstack_compute_keypair_v2.this.name
}

output "router_id" {
  description = "ID du routeur"
  value       = openstack_networking_router_v2.this.id
}
