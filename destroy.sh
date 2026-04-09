#!/bin/bash
set -e

echo "=== Nettoyage interface routeur ==="
SUBNET_ID=$(openstack subnet list | grep landing-zone-demo | awk '{print $2}')

if [ -n "$SUBNET_ID" ]; then
  openstack router remove subnet landing-zone-demo-router $SUBNET_ID && \
  echo "Interface détachée : $SUBNET_ID" || \
  echo "Aucune interface à détacher"
fi

echo "=== Terraform destroy ==="
terraform destroy "$@"