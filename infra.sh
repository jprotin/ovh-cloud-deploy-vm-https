#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENVS_DIR="$SCRIPT_DIR/envs"
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
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
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

# -------------------------------------------------------
# Help
# -------------------------------------------------------
usage() {
  cat <<EOF
${BOLD}Usage:${NC} $(basename "$0") <commande> [options]

${BOLD}Commandes :${NC}
  init      [-e env]               Initialise Terraform (terraform init)
  plan      [-e env]               Prévisualise les changements (terraform plan)
  deploy    [-e env] [-a]          Déploie l'infrastructure (terraform apply)
  destroy   [-e env] [-a]          Détruit l'infrastructure
  ssh       [-e env] [-u user]     Connexion SSH à la VM
  output    [-e env]               Affiche les outputs Terraform
  status    [-e env]               Affiche l'état des ressources
  envs                             Liste les environnements disponibles

${BOLD}Options :${NC}
  -e, --env ENV       Environnement cible (défaut: $DEFAULT_ENV)
  -u, --user USER     Utilisateur SSH (défaut: ubuntu)
  -a, --auto-approve  Applique sans confirmation (deploy/destroy)
  -h, --help          Affiche cette aide

${BOLD}Exemples :${NC}
  $(basename "$0") deploy                        # Déploie sandbox-sbg5
  $(basename "$0") deploy -e sandbox-sbg5 -a     # Déploie sans confirmation
  $(basename "$0") ssh                            # SSH vers sandbox-sbg5
  $(basename "$0") ssh -e sandbox-sbg5 -u root    # SSH en root
  $(basename "$0") destroy -e sandbox-sbg5        # Détruit avec confirmation
  $(basename "$0") output -e sandbox-sbg5         # Affiche les outputs

EOF
}

# -------------------------------------------------------
# Commandes
# -------------------------------------------------------
cmd_init() {
  local env="$1"
  check_env "$env"
  info "Initialisation de l'environnement ${BOLD}$env${NC}"
  terraform -chdir="$(env_dir "$env")" init
  ok "Initialisation terminée"
}

cmd_plan() {
  local env="$1"
  check_env "$env"
  info "Plan de l'environnement ${BOLD}$env${NC}"
  terraform -chdir="$(env_dir "$env")" plan
}

cmd_deploy() {
  local env="$1"
  local auto_approve="$2"
  check_env "$env"

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

  local dir
  dir="$(env_dir "$env")"

  # Détacher l'interface routeur (spécifique OVHcloud)
  info "Nettoyage de l'interface routeur..."
  local project_name
  project_name=$(terraform -chdir="$dir" output -raw vm_name 2>/dev/null | sed 's/-vm$//' || echo "")

  if [ -n "$project_name" ]; then
    local subnet_id
    subnet_id=$(openstack subnet list 2>/dev/null | grep "$project_name" | awk '{print $2}' || echo "")
    if [ -n "$subnet_id" ]; then
      openstack router remove subnet "${project_name}-router" "$subnet_id" \
        && ok "Interface routeur détachée" \
        || warn "Aucune interface à détacher"
    else
      info "Aucun subnet à détacher"
    fi
  else
    warn "Impossible de déterminer le nom du projet, skip du nettoyage routeur"
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
  ip=$(terraform -chdir="$dir" output -raw vm_public_ip 2>/dev/null || echo "")

  if [ -z "$ip" ]; then
    error "Impossible de récupérer l'IP publique. L'infrastructure est-elle déployée ?"
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

# -------------------------------------------------------
# Parsing des arguments
# -------------------------------------------------------
COMMAND="${1:-}"
[ -z "$COMMAND" ] && { usage; exit 0; }
shift

ENV="$DEFAULT_ENV"
USER_SSH="ubuntu"
AUTO_APPROVE="false"

while [ $# -gt 0 ]; do
  case "$1" in
    -e|--env)
      ENV="$2"; shift 2 ;;
    -u|--user)
      USER_SSH="$2"; shift 2 ;;
    -a|--auto-approve)
      AUTO_APPROVE="true"; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      error "Option inconnue : $1"
      usage
      exit 1 ;;
  esac
done

# -------------------------------------------------------
# Dispatch
# -------------------------------------------------------
case "$COMMAND" in
  init)     cmd_init "$ENV" ;;
  plan)     cmd_plan "$ENV" ;;
  deploy)   cmd_deploy "$ENV" "$AUTO_APPROVE" ;;
  destroy)  cmd_destroy "$ENV" "$AUTO_APPROVE" ;;
  ssh)      cmd_ssh "$ENV" "$USER_SSH" ;;
  output)   cmd_output "$ENV" ;;
  status)   cmd_status "$ENV" ;;
  envs)     list_envs ;;
  -h|--help|help)
            usage ;;
  *)
    error "Commande inconnue : $COMMAND"
    usage
    exit 1 ;;
esac
