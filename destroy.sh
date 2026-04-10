#!/bin/bash
set -e

ENV_DIR="${1:-envs/sandbox-sbg5}"

echo "=== Nettoyage interface routeur ==="
SUBNET_ID=$(openstack subnet list | grep landing-zone-demo | awk '{print $2}')

if [ -n "$SUBNET_ID" ]; then
  openstack router remove subnet landing-zone-demo-router "$SUBNET_ID" && \
  echo "Interface détachée : $SUBNET_ID" || \
  echo "Aucune interface à détacher"
fi

echo "=== Terraform destroy ($ENV_DIR) ==="
cd "$ENV_DIR"
terraform destroy "${@:2}"
