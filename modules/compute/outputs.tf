output "vm_name" {
  description = "Nom de la VM"
  value       = openstack_compute_instance_v2.this.name
}

output "vm_id" {
  description = "ID de la VM"
  value       = openstack_compute_instance_v2.this.id
}

output "private_ip" {
  description = "IP privée de la VM"
  value       = openstack_networking_port_v2.this.all_fixed_ips[0]
}

output "public_ip" {
  description = "IP publique flottante"
  value       = openstack_networking_floatingip_v2.this.address
}
