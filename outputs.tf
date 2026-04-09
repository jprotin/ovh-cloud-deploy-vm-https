output "vm_name" {
  description = "Nom de la VM"
  value       = openstack_compute_instance_v2.vm.name
}

output "vm_private_ip" {
  description = "IP privée de la VM"
  value       = openstack_networking_port_v2.vm_port.all_fixed_ips[0]
}

output "vm_public_ip" {
  description = "IP publique flottante"
  value       = openstack_networking_floatingip_v2.floating_ip.address
}

output "ssh_command" {
  description = "Commande SSH pour se connecter"
  value       = "ssh ubuntu@${openstack_networking_floatingip_v2.floating_ip.address}"
}