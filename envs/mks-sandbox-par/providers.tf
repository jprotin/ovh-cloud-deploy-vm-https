provider "ovh" {
  endpoint           = "ovh-eu"
  application_key    = var.ovh_application_key
  application_secret = var.ovh_application_secret
  consumer_key       = var.ovh_consumer_key
}

# Requis pour provisionner le réseau privé + subnet via modules/network
provider "openstack" {
  # checkov:skip=CKV_OPENSTACK_1: password via variable sensitive ou env var TF_VAR_os_password
  auth_url      = var.os_auth_url
  tenant_id     = var.os_tenant_id
  tenant_name   = var.os_tenant_name
  user_name     = var.os_username
  password      = var.os_password
  region        = var.os_region
  endpoint_type = "public"
}
