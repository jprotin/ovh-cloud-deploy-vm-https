# OVH API
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

# Tenant OVH Public Cloud (service_name)
variable "ovh_service_name" {
  description = "ID du projet Public Cloud OVHcloud"
  type        = string
}

# Projet
variable "project_name" {
  type    = string
  default = "mks-sandbox-par"
}

variable "cluster_name" {
  type    = string
  default = "mks-sandbox-par"
}

# Région MKS : Paris 3AZ par défaut
variable "region" {
  type    = string
  default = "EU-WEST-PAR"
}

variable "kube_version" {
  description = "Version de Kubernetes (null = latest stable MKS)"
  type        = string
  default     = null
}

# Multi-AZ : 2 zones par défaut
variable "az_count" {
  description = "Nombre d'AZ pour la répartition des workers (1, 2 ou 3)"
  type        = number
  default     = 2
}

variable "node_flavor" {
  type    = string
  default = "b2-7"
}

variable "nodes_per_pool" {
  description = "Nombre de nodes par AZ"
  type        = number
  default     = 1
}

variable "api_allowed_cidrs" {
  description = "Liste des CIDR autorisés à accéder à l'API Kube (vide = 0.0.0.0/0)"
  type        = list(string)
  default     = []
}
