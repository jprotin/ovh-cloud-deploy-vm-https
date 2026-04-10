variable "project_name" {
  description = "Nom du projet (préfixe des ressources)"
  type        = string
}

variable "region" {
  description = "Région OpenStack"
  type        = string
}

variable "network_id" {
  description = "ID du réseau privé"
  type        = string
}

variable "subnet_id" {
  description = "ID du subnet"
  type        = string
}

variable "secgroup_id" {
  description = "ID du security group"
  type        = string
}

variable "keypair_name" {
  description = "Nom de la keypair SSH"
  type        = string
}

variable "image_name" {
  description = "Nom de l'image OS"
  type        = string
  default     = "Ubuntu 24.04"
}

variable "flavor_name" {
  description = "Nom du flavor (taille de la VM)"
  type        = string
  default     = "d2-2"
}

variable "user_data" {
  description = "Contenu cloud-init (user_data)"
  type        = string
  default     = null
}

variable "metadata" {
  description = "Metadata de l'instance"
  type        = map(string)
  default     = {}
}
