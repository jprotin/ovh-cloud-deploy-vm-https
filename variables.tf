# OVH API
variable "ovh_application_key" {}
variable "ovh_application_secret" {}
variable "ovh_consumer_key" {}

# OpenStack
variable "os_auth_url" {
  default = "https://auth.cloud.ovh.net/v3"
}
variable "os_tenant_id" {}
variable "os_tenant_name" {}
variable "os_username" {}
variable "os_password" {}
variable "os_region" {
  default = "SBG5"
}

# Projet
variable "project_name" {
  default = "landing-zone-demo"
}

variable "ssh_public_key" {
  description = "Contenu de la clé publique SSH"
}

variable "admin_cidr" {
  description = "Ton IP publique autorisée en SSH (ex: 90.x.x.x/32)"
  # Trouve ton IP : curl ifconfig.me
}