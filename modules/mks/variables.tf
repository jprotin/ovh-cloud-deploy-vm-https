variable "service_name" {
  description = "Identifiant du projet Public Cloud OVHcloud (tenant ID)"
  type        = string
}

variable "cluster_name" {
  description = "Nom du cluster MKS"
  type        = string
}

variable "region" {
  description = "Région OVHcloud supportant MKS (ex: EU-WEST-PAR pour Paris 3AZ, SBG5)"
  type        = string
}

variable "kube_version" {
  description = "Version de Kubernetes (ex: 1.32). Null pour la latest stable supportée MKS."
  type        = string
  default     = null
}

variable "update_policy" {
  description = "Politique de mise à jour du cluster (ALWAYS_UPDATE, MINIMAL_DOWNTIME, NEVER_UPDATE)"
  type        = string
  default     = "MINIMAL_DOWNTIME"

  validation {
    condition     = contains(["ALWAYS_UPDATE", "MINIMAL_DOWNTIME", "NEVER_UPDATE"], var.update_policy)
    error_message = "update_policy doit être ALWAYS_UPDATE, MINIMAL_DOWNTIME ou NEVER_UPDATE."
  }
}

variable "az_count" {
  description = "Nombre d'availability zones sur lesquelles répartir les node pools (1, 2 ou 3). 1 = mono-AZ, 2 ou 3 = multi-AZ (région 3AZ requise)."
  type        = number
  default     = 2

  validation {
    condition     = contains([1, 2, 3], var.az_count)
    error_message = "az_count doit être 1, 2 ou 3."
  }
}


variable "node_flavor" {
  description = "Flavor des workers (ex: b2-7)"
  type        = string
  default     = "b2-7"
}

variable "nodes_per_pool" {
  description = "Nombre de nodes par node pool (= par AZ en multi-AZ)"
  type        = number
  default     = 1
}

variable "autoscale" {
  description = "Active l'autoscaling sur les node pools"
  type        = bool
  default     = false
}

variable "min_nodes_per_pool" {
  description = "Nombre minimum de nodes par pool (autoscaling)"
  type        = number
  default     = 1
}

variable "max_nodes_per_pool" {
  description = "Nombre maximum de nodes par pool (autoscaling)"
  type        = number
  default     = 3
}

variable "api_allowed_cidrs" {
  description = "Liste des CIDR autorisés à accéder à l'API Kube. Vide = 0.0.0.0/0 (ouvert)."
  type        = list(string)
  default     = []
}

variable "private_network_id" {
  description = "ID du réseau privé OpenStack (null = cluster public)"
  type        = string
  default     = null
}
