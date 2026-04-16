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

# -------------------------------------------------------
# Feature flags : tout activé par défaut (backward-compat)
# -------------------------------------------------------
variable "enable_router" {
  description = "Crée le routeur + interface vers le réseau externe (requis pour l'accès Internet des VMs)"
  type        = bool
  default     = true
}

variable "enable_secgroup" {
  description = "Crée un security group de base (SSH/ICMP/HTTP/HTTPS)"
  type        = bool
  default     = true
}

variable "enable_keypair" {
  description = "Crée une keypair OpenStack (pour SSH sur les VMs)"
  type        = bool
  default     = true
}

# -------------------------------------------------------
# Variables conditionnelles (selon les flags)
# -------------------------------------------------------
variable "ext_net_id" {
  description = "ID du réseau externe (Ext-Net). Requis si enable_router = true."
  type        = string
  default     = null
}

variable "admin_cidr" {
  description = "CIDR autorisé en SSH (ex: 90.x.x.x/32). Requis si enable_secgroup = true."
  type        = string
  default     = null
}

variable "ssh_public_key" {
  description = "Contenu de la clé publique SSH. Requis si enable_keypair = true."
  type        = string
  default     = null
}

# -------------------------------------------------------
# Validations : cohérence flag ↔ variable requise
# -------------------------------------------------------
# Note : on ne peut pas croiser plusieurs variables dans un validation block classique.
# On utilise des preconditions au niveau du main.tf via lifecycle, ou on laisse l'erreur
# OpenStack native remonter si ext_net_id/admin_cidr/ssh_public_key manque.
