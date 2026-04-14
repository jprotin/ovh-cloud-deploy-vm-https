#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_DIR="$PROJECT_DIR/envs/sandbox-sbg5"

# -------------------------------------------------------
# Versions minimales requises
# -------------------------------------------------------
MIN_TERRAFORM="1.5.0"
MIN_OPENSTACK="6.0.0"
MIN_GIT="2.34.0"
MIN_KUBECTL="1.28.0"

# -------------------------------------------------------
# Couleurs
# -------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# -------------------------------------------------------
# Fonctions utilitaires
# -------------------------------------------------------
info() { echo -e "${CYAN}[INFO]${NC}    $*"; }
ok() { echo -e "${GREEN}[OK]${NC}      $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}    $*"; }
error() { echo -e "${RED}[ERROR]${NC}   $*" >&2; }
install() { echo -e "${YELLOW}[INSTALL]${NC} $*"; }

ACTIONS_DONE=0

# Compare deux versions semver. Retourne 0 si $1 >= $2
version_gte() {
  local v1="$1"
  local v2="$2"

  # Extraire les composants majeur.mineur.patch
  local v1_major v1_minor v1_patch
  local v2_major v2_minor v2_patch

  IFS='.' read -r v1_major v1_minor v1_patch <<<"$v1"
  IFS='.' read -r v2_major v2_minor v2_patch <<<"$v2"

  v1_major="${v1_major:-0}"
  v1_minor="${v1_minor:-0}"
  v1_patch="${v1_patch:-0}"
  v2_major="${v2_major:-0}"
  v2_minor="${v2_minor:-0}"
  v2_patch="${v2_patch:-0}"

  if ((v1_major > v2_major)); then return 0; fi
  if ((v1_major < v2_major)); then return 1; fi
  if ((v1_minor > v2_minor)); then return 0; fi
  if ((v1_minor < v2_minor)); then return 1; fi
  if ((v1_patch >= v2_patch)); then return 0; fi
  return 1
}

# Extrait un numéro de version depuis une sortie de commande
extract_version() {
  echo "$1" | grep -oP '\d+\.\d+(\.\d+)?' | head -1
}

# -------------------------------------------------------
# Vérification : Terraform
# -------------------------------------------------------
check_terraform() {
  echo ""
  info "Vérification de Terraform (>= $MIN_TERRAFORM)..."

  if ! command -v terraform &>/dev/null; then
    install "Terraform non trouvé, installation en cours..."
    install_terraform
    ACTIONS_DONE=$((ACTIONS_DONE + 1))
    return
  fi

  local current
  current=$(extract_version "$(terraform -version 2>/dev/null | head -1)")

  if version_gte "$current" "$MIN_TERRAFORM"; then
    ok "Terraform $current"
  else
    warn "Terraform $current < $MIN_TERRAFORM, mise à jour en cours..."
    install_terraform
    ACTIONS_DONE=$((ACTIONS_DONE + 1))
  fi
}

install_terraform() {
  # Vérifier si le dépôt HashiCorp est configuré
  if [ ! -f /usr/share/keyrings/hashicorp-archive-keyring.gpg ]; then
    info "Ajout du dépôt HashiCorp..."
    wget -qO- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" |
      sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  fi

  sudo apt-get update -qq
  sudo apt-get install -y -qq terraform

  local new_version
  new_version=$(extract_version "$(terraform -version 2>/dev/null | head -1)")
  ok "Terraform $new_version installé"
}

# -------------------------------------------------------
# Vérification : Client OpenStack
# -------------------------------------------------------
check_openstack() {
  echo ""
  info "Vérification du client OpenStack (>= $MIN_OPENSTACK)..."

  if ! command -v openstack &>/dev/null; then
    install "Client OpenStack non trouvé, installation en cours..."
    install_openstack
    ACTIONS_DONE=$((ACTIONS_DONE + 1))
    return
  fi

  local current
  current=$(extract_version "$(openstack --version 2>&1)")

  if version_gte "$current" "$MIN_OPENSTACK"; then
    ok "python-openstackclient $current"
  else
    warn "python-openstackclient $current < $MIN_OPENSTACK, mise à jour en cours..."
    install_openstack
    ACTIONS_DONE=$((ACTIONS_DONE + 1))
  fi
}

install_openstack() {
  sudo apt-get update -qq
  sudo apt-get install -y -qq python3-openstackclient

  local new_version
  new_version=$(extract_version "$(openstack --version 2>&1)")
  ok "python-openstackclient $new_version installé"
}

# -------------------------------------------------------
# Vérification : Git
# -------------------------------------------------------
check_git() {
  echo ""
  info "Vérification de Git (>= $MIN_GIT)..."

  if ! command -v git &>/dev/null; then
    install "Git non trouvé, installation en cours..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq git
    ACTIONS_DONE=$((ACTIONS_DONE + 1))

    local new_version
    new_version=$(extract_version "$(git --version 2>/dev/null)")
    ok "Git $new_version installé"
    return
  fi

  local current
  current=$(extract_version "$(git --version 2>/dev/null)")

  if version_gte "$current" "$MIN_GIT"; then
    ok "Git $current"
  else
    warn "Git $current < $MIN_GIT, mise à jour en cours..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq git
    ACTIONS_DONE=$((ACTIONS_DONE + 1))

    local new_version
    new_version=$(extract_version "$(git --version 2>/dev/null)")
    ok "Git $new_version installé"
  fi
}

# -------------------------------------------------------
# Vérification : kubectl (optionnel — requis pour MKS)
# -------------------------------------------------------
check_kubectl() {
  echo ""
  info "Vérification de kubectl (>= $MIN_KUBECTL, requis pour MKS)..."

  if ! command -v kubectl &>/dev/null; then
    install "kubectl non trouvé, installation en cours..."
    install_kubectl
    ACTIONS_DONE=$((ACTIONS_DONE + 1))
    return
  fi

  local current
  current=$(extract_version "$(kubectl version --client 2>/dev/null | head -1)")

  if [ -z "$current" ]; then
    warn "Impossible de déterminer la version de kubectl, skip"
    return
  fi

  if version_gte "$current" "$MIN_KUBECTL"; then
    ok "kubectl $current"
  else
    warn "kubectl $current < $MIN_KUBECTL, mise à jour en cours..."
    install_kubectl
    ACTIONS_DONE=$((ACTIONS_DONE + 1))
  fi
}

install_kubectl() {
  # Installation via le dépôt officiel Kubernetes
  if [ ! -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]; then
    info "Ajout du dépôt Kubernetes..."
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key |
      sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /" |
      sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
  fi

  sudo apt-get update -qq
  sudo apt-get install -y -qq kubectl

  local new_version
  new_version=$(extract_version "$(kubectl version --client 2>/dev/null | head -1)")
  ok "kubectl $new_version installé"
}

# -------------------------------------------------------
# Vérification : Clé SSH
# -------------------------------------------------------
check_ssh_key() {
  echo ""
  info "Vérification de la clé SSH..."

  if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
    ok "Clé SSH ED25519 présente ($HOME/.ssh/id_ed25519.pub)"
  elif [ -f "$HOME/.ssh/id_rsa.pub" ]; then
    ok "Clé SSH RSA présente ($HOME/.ssh/id_rsa.pub)"
  else
    warn "Aucune clé SSH trouvée"
    echo ""
    echo "  Génère une clé SSH avec :"
    echo "    ssh-keygen -t ed25519 -C \"terraform-ovh\""
    echo ""
    echo "  Puis copie le contenu de la clé publique dans terraform.tfvars :"
    echo "    cat ~/.ssh/id_ed25519.pub"
    echo ""
    ACTIONS_DONE=$((ACTIONS_DONE + 1))
  fi
}

# -------------------------------------------------------
# Vérification : terraform.tfvars
# -------------------------------------------------------
check_tfvars() {
  echo ""
  info "Vérification de terraform.tfvars..."

  if [ -f "$ENV_DIR/terraform.tfvars" ]; then
    ok "terraform.tfvars présent ($ENV_DIR/terraform.tfvars)"
  else
    warn "terraform.tfvars absent"
    echo ""
    echo "  Crée-le à partir du template :"
    echo "    cp $ENV_DIR/terraform.tfvars.dist $ENV_DIR/terraform.tfvars"
    echo "    # Puis édite-le avec tes valeurs"
    echo ""
    ACTIONS_DONE=$((ACTIONS_DONE + 1))
  fi
}

# -------------------------------------------------------
# Terraform init
# -------------------------------------------------------
check_terraform_init() {
  echo ""
  info "Vérification de l'initialisation Terraform..."

  if [ -d "$ENV_DIR/.terraform" ]; then
    ok "Terraform déjà initialisé ($ENV_DIR)"
  else
    install "Lancement de terraform init..."
    terraform -chdir="$ENV_DIR" init
    ACTIONS_DONE=$((ACTIONS_DONE + 1))
    ok "Terraform initialisé"
  fi
}

# -------------------------------------------------------
# Main
# -------------------------------------------------------
echo ""
echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  Setup environnement de travail${NC}"
echo -e "${BOLD}  OVHcloud Landing Zone IaC${NC}"
echo -e "${BOLD}========================================${NC}"

check_terraform
check_openstack
check_git
check_kubectl
check_ssh_key
check_tfvars
check_terraform_init

echo ""
echo -e "${BOLD}----------------------------------------${NC}"

if [ "$ACTIONS_DONE" -eq 0 ]; then
  echo ""
  echo -e "  ${GREEN}${BOLD}Ton environnement est déjà prêt.${NC}"
  echo ""
else
  echo ""
  echo -e "  ${CYAN}${BOLD}$ACTIONS_DONE action(s) effectuée(s).${NC}"
  echo ""
fi

echo -e "${BOLD}----------------------------------------${NC}"
echo ""
