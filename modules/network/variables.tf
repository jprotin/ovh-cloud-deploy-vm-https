variable "project_name" {
  description = "Nom du projet (préfixe des ressources)"
  type        = string
}

variable "region" {
  description = "Région OpenStack"
  type        = string
}

variable "subnet_cidr" {
  description = "CIDR du subnet privé"
  type        = string
  default     = "10.0.1.0/24"
}

variable "dns_nameservers" {
  description = "Serveurs DNS du subnet"
  type        = list(string)
  default     = ["213.186.33.99", "8.8.8.8"]
}

variable "ext_net_id" {
  description = "ID du réseau externe (Ext-Net)"
  type        = string
}

variable "admin_cidr" {
  description = "CIDR autorisé en SSH (ex: 90.x.x.x/32)"
  type        = string
}

variable "ssh_public_key" {
  description = "Contenu de la clé publique SSH"
  type        = string
}
