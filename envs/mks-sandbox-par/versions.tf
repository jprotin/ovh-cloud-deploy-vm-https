terraform {
  required_version = ">= 1.5.0"

  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "~> 0.46"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}
