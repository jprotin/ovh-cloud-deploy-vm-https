# -------------------------------------------------------
# OVH API
# -------------------------------------------------------
variable "ovh_application_key" {
  type      = string
  sensitive = true
}
variable "ovh_application_secret" {
  type      = string
  sensitive = true
}
variable "ovh_consumer_key" {
  type      = string
  sensitive = true
}
variable "ovh_service_name" {
  description = "ID du projet Public Cloud OVHcloud (tenant)"
  type        = string
}

# -------------------------------------------------------
# OpenStack (utilisé uniquement si enable_vm = true)
# -------------------------------------------------------
variable "os_auth_url" {
  type    = string
  default = "https://auth.cloud.ovh.net/v3"
}
variable "os_tenant_id" {
  type    = string
  default = ""
}
variable "os_tenant_name" {
  type    = string
  default = ""
}
variable "os_username" {
  type    = string
  default = ""
}
variable "os_password" {
  type      = string
  default   = ""
  sensitive = true
}
variable "os_region" {
  type    = string
  default = "GRA11"
}

# -------------------------------------------------------
# Feature flags
# -------------------------------------------------------
variable "enable_vm" {
  description = "Déploie une VM (requiert les credentials OpenStack)"
  type        = bool
  default     = false
}

variable "enable_mks" {
  description = "Déploie un cluster Kubernetes managé (MKS)"
  type        = bool
  default     = false
}

variable "enable_dbaas" {
  description = "Déploie une base de données managée (DBaaS)"
  type        = bool
  default     = false

  validation {
    condition     = var.enable_dbaas == false
    error_message = "Le module DBaaS n'est pas encore implémenté. Garder enable_dbaas = false."
  }
}

# -------------------------------------------------------
# Projet
# -------------------------------------------------------
variable "project_name" {
  type    = string
  default = "sandbox-par"
}

# -------------------------------------------------------
# VM (si enable_vm = true)
# -------------------------------------------------------
variable "ssh_public_key" {
  description = "Contenu de la clé publique SSH (requis si enable_vm)"
  type        = string
  default     = ""
}

variable "admin_cidr" {
  description = "CIDR autorisé en SSH (requis si enable_vm, ex: XX.XX.XX.XX/32). Pas de default : forcer un CIDR restreint."
  type        = string

  validation {
    condition     = var.admin_cidr != "0.0.0.0/0"
    error_message = "admin_cidr ne peut pas être 0.0.0.0/0 (ouverture SSH au monde entier interdite)."
  }
}

variable "vm_image_name" {
  type    = string
  default = "Ubuntu 24.04"
}

variable "vm_flavor" {
  type    = string
  default = "d2-2"
}

# -------------------------------------------------------
# MKS (si enable_mks = true)
# -------------------------------------------------------
variable "mks_region" {
  description = "Région MKS (ex: EU-WEST-PAR pour Paris 3AZ)"
  type        = string
  default     = "EU-WEST-PAR"
}

variable "mks_version" {
  description = "Version Kubernetes (null = latest stable MKS)"
  type        = string
  default     = null
}

variable "mks_az_count" {
  description = "Nombre d'AZ pour les workers (1, 2 ou 3)"
  type        = number
  default     = 2
}


variable "mks_node_flavor" {
  type    = string
  default = "b2-7"
}

variable "mks_nodes_per_pool" {
  type    = number
  default = 1
}

variable "mks_api_allowed_cidrs" {
  type    = list(string)
  default = []
}
