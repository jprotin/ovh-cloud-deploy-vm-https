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

# OpenStack
variable "os_auth_url" {
  type    = string
  default = "https://auth.cloud.ovh.net/v3"
}
variable "os_tenant_id" {
  type = string
}
variable "os_tenant_name" {
  type = string
}
variable "os_username" {
  type = string
}
variable "os_password" {
  type      = string
  sensitive = true
}
variable "os_region" {
  type    = string
  default = "SBG5"
}

# Projet
variable "project_name" {
  type    = string
  default = "landing-zone-demo"
}

variable "ssh_public_key" {
  description = "Contenu de la clé publique SSH"
  type        = string
}

variable "admin_cidr" {
  description = "CIDR autorisé en SSH (ex: 90.x.x.x/32)"
  type        = string

  validation {
    condition     = var.admin_cidr != "0.0.0.0/0"
    error_message = "admin_cidr ne peut pas être 0.0.0.0/0 (ouverture SSH au monde entier interdite)."
  }
}
