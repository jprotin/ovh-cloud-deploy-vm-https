#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENVS_DIR="$SCRIPT_DIR/envs"
EXAMPLES_DIR="$SCRIPT_DIR/examples"
DEFAULT_ENV="sandbox-sbg5"

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
info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

env_dir() {
  local env="$1"
  echo "$ENVS_DIR/$env"
}

check_env() {
  local dir
  dir="$(env_dir "$1")"
  if [ ! -d "$dir" ]; then
    error "Environnement '$1' introuvable dans $ENVS_DIR/"
    echo ""
    list_envs
    exit 1
  fi
}

list_envs() {
  info "Environnements disponibles :"
  for d in "$ENVS_DIR"/*/; do
    [ -d "$d" ] && echo "  - $(basename "$d")"
  done
}

# Retourne un output Terraform -raw ou une chaîne vide
tf_output_raw() {
  local dir="$1"
  local name="$2"
  terraform -chdir="$dir" output -raw "$name" 2>/dev/null || echo ""
}

# Détecte la région cible d'un env (priorité : terraform.tfvars > nom de l'env)
detect_region() {
  local env="$1"
  local tfvars
  tfvars="$(env_dir "$env")/terraform.tfvars"
  local region=""
  if [ -f "$tfvars" ]; then
    region=$(grep -E '^[[:space:]]*region[[:space:]]*=' "$tfvars" | head -1 | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/')
  fi
  if [ -z "$region" ]; then
    case "$env" in
      *par*) region="EU-WEST-PAR" ;;
      *sbg*) region="SBG5" ;;
    esac
  fi
  echo "$region"
}

# Source le bon openrc en fonction de la région cible (warning + continue si absent)
source_openrc() {
  local env="$1"
  local region openrc
  region=$(detect_region "$env")
  case "$region" in
    *PAR*) openrc="$SCRIPT_DIR/openrc_PAR.sh" ;;
    *SBG*) openrc="$SCRIPT_DIR/openrc_SBG.sh" ;;
    *)
      warn "Région inconnue pour env '$env' (region='$region') — pas de sourcing openrc"
      return 0
      ;;
  esac
  if [ ! -f "$openrc" ]; then
    warn "Fichier $(basename "$openrc") absent — pas de sourcing (vérifie OS_* en env si besoin)"
    return 0
  fi
  info "Sourcing $(basename "$openrc")"
  set +u
  # shellcheck source=/dev/null
  . "$openrc"
  set -u
}

# -------------------------------------------------------
# Help
# -------------------------------------------------------
usage() {
  cat <<EOF
${BOLD}Usage:${NC} $(basename "$0") <commande> [options]

${BOLD}Commandes générales :${NC}
  init           [-e env]          Initialise Terraform (terraform init)
  plan           [-e env]          Prévisualise les changements
  deploy         [-e env] [-a]     Déploie l'infrastructure
  destroy        [-e env] [-a]     Détruit l'infrastructure
  output         [-e env]          Affiche les outputs Terraform
  status         [-e env]          Affiche l'état des ressources
  envs                             Liste les environnements disponibles

${BOLD}Commandes VM :${NC}
  ssh            [-e env] [-u user]   Connexion SSH à la VM

${BOLD}Commandes MKS :${NC}
  kubeconfig     [-e env]             Affiche la commande export KUBECONFIG
  deploy-demo    [-e env]             Déploie la démo multi-AZ (examples/k8s-multi-az-demo/)
  destroy-demo   [-e env]             Supprime la démo multi-AZ

${BOLD}Options :${NC}
  -e, --env ENV       Environnement cible (défaut: $DEFAULT_ENV)
  -u, --user USER     Utilisateur SSH (défaut: ubuntu)
  -a, --auto-approve  Applique sans confirmation (deploy/destroy)
  -h, --help          Affiche cette aide

${BOLD}Exemples :${NC}
  $(basename "$0") deploy -e sandbox-sbg5          # Déploie la VM
  $(basename "$0") deploy -e mks-sandbox-par       # Déploie le cluster MKS
  $(basename "$0") kubeconfig -e mks-sandbox-par   # Exporte kubeconfig
  $(basename "$0") deploy-demo -e mks-sandbox-par  # Déploie la démo multi-AZ
  $(basename "$0") ssh -e sandbox-sbg5              # SSH vers la VM

EOF
}

# -------------------------------------------------------
# Commandes
# -------------------------------------------------------
cmd_init() {
  local env="$1"
  check_env "$env"
  source_openrc "$env"
  info "Initialisation de l'environnement ${BOLD}$env${NC}"
  terraform -chdir="$(env_dir "$env")" init
  ok "Initialisation terminée"
}

cmd_plan() {
  local env="$1"
  check_env "$env"
  source_openrc "$env"
  info "Plan de l'environnement ${BOLD}$env${NC}"
  terraform -chdir="$(env_dir "$env")" plan
}

cmd_deploy() {
  local env="$1"
  local auto_approve="$2"
  check_env "$env"
  source_openrc "$env"

  local dir
  dir="$(env_dir "$env")"

  # Init automatique si nécessaire
  if [ ! -d "$dir/.terraform" ]; then
    warn "Terraform non initialisé, lancement de 'terraform init'..."
    terraform -chdir="$dir" init
  fi

  info "Déploiement de l'environnement ${BOLD}$env${NC}"

  if [ "$auto_approve" = "true" ]; then
    terraform -chdir="$dir" apply -auto-approve
  else
    terraform -chdir="$dir" apply
  fi

  ok "Déploiement terminé"
  echo ""
  terraform -chdir="$dir" output
}

cmd_destroy() {
  local env="$1"
  local auto_approve="$2"
  check_env "$env"
  source_openrc "$env"

  local dir
  dir="$(env_dir "$env")"

  # Détacher l'interface routeur (spécifique OVHcloud, uniquement si VM déployée)
  local vm_name
  vm_name=$(tf_output_raw "$dir" "vm_name")
  if [ -n "$vm_name" ] && [ "$vm_name" != "null" ]; then
    info "Nettoyage de l'interface routeur..."
    local project_name="${vm_name%-vm}"
    local subnet_id
    subnet_id=$(openstack subnet list 2>/dev/null | grep "$project_name" | awk '{print $2}' || echo "")
    if [ -n "$subnet_id" ]; then
      if openstack router remove subnet "${project_name}-router" "$subnet_id"; then
        ok "Interface routeur détachée"
      else
        warn "Aucune interface à détacher"
      fi
    else
      info "Aucun subnet à détacher"
    fi
  fi

  info "Destruction de l'environnement ${BOLD}$env${NC}"

  if [ "$auto_approve" = "true" ]; then
    terraform -chdir="$dir" destroy -auto-approve
  else
    terraform -chdir="$dir" destroy
  fi

  ok "Destruction terminée"
}

cmd_ssh() {
  local env="$1"
  local user="$2"
  check_env "$env"

  local dir
  dir="$(env_dir "$env")"

  local ip
  ip=$(tf_output_raw "$dir" "vm_public_ip")

  if [ -z "$ip" ] || [ "$ip" = "null" ]; then
    error "Aucune VM déployée dans l'environnement '$env'."
    error "Vérifie que 'enable_vm = true' (env flexibles) ou que l'env contient une VM."
    exit 1
  fi

  info "Connexion SSH ${BOLD}${user}@${ip}${NC}"
  ssh "$user@$ip"
}

cmd_output() {
  local env="$1"
  check_env "$env"
  terraform -chdir="$(env_dir "$env")" output
}

cmd_status() {
  local env="$1"
  check_env "$env"

  local dir
  dir="$(env_dir "$env")"

  if [ ! -f "$dir/terraform.tfstate" ] && [ ! -d "$dir/.terraform" ]; then
    warn "Environnement non initialisé"
    return
  fi

  terraform -chdir="$dir" show -no-color 2>/dev/null | head -50
  local total
  total=$(terraform -chdir="$dir" state list 2>/dev/null | wc -l || echo "0")
  echo ""
  info "${BOLD}${total}${NC} ressource(s) dans le state"
}

cmd_wait_nodes() {
  local env="$1"
  local timeout="$2"
  check_env "$env"

  local dir kubeconfig
  dir="$(env_dir "$env")"
  kubeconfig=$(tf_output_raw "$dir" "kubeconfig_path")

  if [ -z "$kubeconfig" ] || [ "$kubeconfig" = "null" ]; then
    error "Aucun cluster MKS dans l'env '$env'."
    exit 1
  fi

  info "Attente que tous les nodes soient Ready (timeout: ${BOLD}${timeout}${NC})"
  KUBECONFIG="$kubeconfig" kubectl wait --for=condition=Ready nodes --all --timeout="$timeout"
  ok "Tous les nodes sont Ready"
  echo ""
  KUBECONFIG="$kubeconfig" kubectl get nodes -o wide
}

cmd_verify() {
  local env="$1"
  check_env "$env"

  local dir
  dir="$(env_dir "$env")"

  echo ""
  info "${BOLD}=== Outputs Terraform ===${NC}"
  terraform -chdir="$dir" output 2>/dev/null || warn "Aucun output (env non déployé ?)"

  local kubeconfig
  kubeconfig=$(tf_output_raw "$dir" "kubeconfig_path")
  if [ -n "$kubeconfig" ] && [ "$kubeconfig" != "null" ] && [ -f "$kubeconfig" ]; then
    echo ""
    info "${BOLD}=== Nodes Kubernetes ===${NC}"
    KUBECONFIG="$kubeconfig" kubectl get nodes -o wide || warn "kubectl get nodes a échoué"
    echo ""
    info "${BOLD}=== Pods (tous namespaces) ===${NC}"
    KUBECONFIG="$kubeconfig" kubectl get pods -A
    echo ""
    info "${BOLD}=== Service zone-demo (si déployé) ===${NC}"
    if KUBECONFIG="$kubeconfig" kubectl get svc zone-demo &>/dev/null; then
      KUBECONFIG="$kubeconfig" kubectl get svc zone-demo
    else
      info "  (démo non déployée)"
    fi
  fi
  echo ""
  ok "Verify terminé"
}

cmd_kubeconfig() {
  local env="$1"
  check_env "$env"

  local dir
  dir="$(env_dir "$env")"

  local kubeconfig
  kubeconfig=$(tf_output_raw "$dir" "kubeconfig_path")

  if [ -z "$kubeconfig" ] || [ "$kubeconfig" = "null" ]; then
    error "Aucun cluster MKS déployé dans l'environnement '$env'."
    error "Vérifie que 'enable_mks = true' (env flexibles) ou que l'env contient MKS."
    exit 1
  fi

  local abs_path
  abs_path=$(cd "$(dirname "$kubeconfig")" && pwd)/$(basename "$kubeconfig")

  if [ ! -f "$abs_path" ]; then
    error "Le fichier kubeconfig n'existe pas : $abs_path"
    error "Déploie d'abord le cluster : ./infra.sh deploy -e $env"
    exit 1
  fi

  info "Kubeconfig pour ${BOLD}$env${NC} :"
  echo ""
  echo "  ${BOLD}export KUBECONFIG=$abs_path${NC}"
  echo ""
  info "Ou en une ligne (à évaluer) :"
  echo ""
  echo "  ${BOLD}eval \$(./infra.sh kubeconfig -e $env | grep export)${NC}"
  echo ""
}

cmd_deploy_demo() {
  local env="$1"
  check_env "$env"

  local dir
  dir="$(env_dir "$env")"

  local kubeconfig
  kubeconfig=$(tf_output_raw "$dir" "kubeconfig_path")

  if [ -z "$kubeconfig" ] || [ "$kubeconfig" = "null" ]; then
    error "Aucun cluster MKS déployé dans l'environnement '$env'."
    exit 1
  fi

  local demo_dir="$EXAMPLES_DIR/k8s-multi-az-demo"
  if [ ! -d "$demo_dir" ]; then
    error "Répertoire de démo introuvable : $demo_dir"
    exit 1
  fi

  info "Déploiement de la démo multi-AZ sur ${BOLD}$env${NC}"
  KUBECONFIG="$kubeconfig" kubectl apply -f "$demo_dir/"

  echo ""
  info "Patiente 1-2 min que l'IP publique du LoadBalancer soit provisionnée, puis :"
  echo ""
  echo "  ${BOLD}KUBECONFIG=$kubeconfig kubectl get svc zone-demo${NC}"
  echo ""
  ok "Démo déployée"
}

cmd_destroy_demo() {
  local env="$1"
  check_env "$env"

  local dir
  dir="$(env_dir "$env")"

  local kubeconfig
  kubeconfig=$(tf_output_raw "$dir" "kubeconfig_path")

  if [ -z "$kubeconfig" ] || [ "$kubeconfig" = "null" ]; then
    error "Aucun cluster MKS déployé dans l'environnement '$env'."
    exit 1
  fi

  local demo_dir="$EXAMPLES_DIR/k8s-multi-az-demo"

  info "Suppression de la démo sur ${BOLD}$env${NC}"
  KUBECONFIG="$kubeconfig" kubectl delete -f "$demo_dir/" --ignore-not-found
  ok "Démo supprimée"
}

# -------------------------------------------------------
# Parsing des arguments
# -------------------------------------------------------
COMMAND="${1:-}"
[ -z "$COMMAND" ] && {
  usage
  exit 0
}
shift

ENV="$DEFAULT_ENV"
USER_SSH="ubuntu"
AUTO_APPROVE="false"
TIMEOUT="5m"

while [ $# -gt 0 ]; do
  case "$1" in
    -e | --env)
      ENV="$2"
      shift 2
      ;;
    -u | --user)
      USER_SSH="$2"
      shift 2
      ;;
    -a | --auto-approve)
      AUTO_APPROVE="true"
      shift
      ;;
    -t | --timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      error "Option inconnue : $1"
      usage
      exit 1
      ;;
  esac
done

# -------------------------------------------------------
# Dispatch
# -------------------------------------------------------
case "$COMMAND" in
  init) cmd_init "$ENV" ;;
  plan) cmd_plan "$ENV" ;;
  deploy) cmd_deploy "$ENV" "$AUTO_APPROVE" ;;
  destroy) cmd_destroy "$ENV" "$AUTO_APPROVE" ;;
  ssh) cmd_ssh "$ENV" "$USER_SSH" ;;
  output) cmd_output "$ENV" ;;
  status) cmd_status "$ENV" ;;
  kubeconfig) cmd_kubeconfig "$ENV" ;;
  wait-nodes) cmd_wait_nodes "$ENV" "$TIMEOUT" ;;
  verify) cmd_verify "$ENV" ;;
  deploy-demo) cmd_deploy_demo "$ENV" ;;
  destroy-demo) cmd_destroy_demo "$ENV" ;;
  envs) list_envs ;;
  -h | --help | help)
    usage
    ;;
  *)
    error "Commande inconnue : $COMMAND"
    usage
    exit 1
    ;;
esac
