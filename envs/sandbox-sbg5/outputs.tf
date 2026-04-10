output "vm_name" {
  description = "Nom de la VM"
  value       = module.vm.vm_name
}

output "vm_private_ip" {
  description = "IP privée de la VM"
  value       = module.vm.private_ip
}

output "vm_public_ip" {
  description = "IP publique flottante"
  value       = module.vm.public_ip
}

output "ssh_command" {
  description = "Commande SSH pour se connecter"
  value       = "ssh ubuntu@${module.vm.public_ip}"
}
