# OVHcloud Public Cloud — Landing Zone IaC

Infrastructure as Code modulaire pour déployer des environnements sur OVHcloud Public Cloud avec Terraform.

## Structure du projet

```
.
├── modules/                      # Modules Terraform réutilisables
│   ├── network/                  # Réseau privé, routeur, security groups, keypair
│   ├── compute/                  # VM générique (instance, port, floating IP)
│   ├── mks/                      # Kubernetes managé (futur)
│   └── dbaas/                    # Bases de données managées (futur)
│
├── envs/                         # Environnements
│   └── sandbox-sbg5/             # Sandbox OVHcloud SBG5
│       ├── main.tf               # Assemblage des modules
│       ├── variables.tf          # Variables d'entrée
│       ├── outputs.tf            # Sorties
│       ├── providers.tf          # Configuration des providers
│       ├── versions.tf           # Contraintes de versions
│       ├── terraform.tfvars      # Valeurs des variables (non versionné)
│       ├── terraform.tfvars.dist # Template de variables
│       └── cloud-init.yaml       # Provisionning de la VM
│
├── _init-project/
│   └── setup.sh                  # Installation automatique des prérequis
├── infra.sh                      # CLI de gestion (deploy, destroy, ssh...)
├── destroy.sh                    # Script de destruction legacy
├── README.md
└── DOCUMENTATION.md
```

## Architecture déployée (sandbox-sbg5)

```
OVHcloud Public Cloud - Région SBG5
│
├── Réseau
│   ├── Réseau privé    : 10.0.1.0/24
│   ├── Routeur         : gateway → Ext-Net (SNAT activé)
│   └── IP flottante    : IP publique assignée dynamiquement
│
├── Sécurité
│   └── Security Group
│       ├── SSH   (22)  → IP admin uniquement
│       ├── HTTP  (80)  → 0.0.0.0/0
│       ├── HTTPS (443) → 0.0.0.0/0
│       └── ICMP        → 0.0.0.0/0
│
└── Compute
    └── VM Ubuntu 24.04
        ├── Flavor  : d2-2 (1 vCPU / 2 GB RAM / 25 GB)
        ├── Nginx   : HTTPS avec certificat auto-signé
        └── Provisionning : cloud-init automatique
```

## Prérequis

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5.0
- [python-openstackclient](https://docs.openstack.org/python-openstackclient/) >= 6.0
- Git >= 2.34
- Un compte OVHcloud avec un projet Public Cloud
- Clés API OVHcloud ([générer ici](https://www.ovh.com/auth/api/createToken))
- Un utilisateur OpenStack créé dans le projet Public Cloud
- Une clé SSH générée localement

### Installation automatique

Le script `_init-project/setup.sh` vérifie et installe tous les outils nécessaires, puis initialise Terraform si besoin :

```bash
./_init-project/setup.sh
```

Le script effectue dans l'ordre :
1. Vérifie/installe **Terraform** (>= 1.5.0)
2. Vérifie/installe **python-openstackclient** (>= 6.0)
3. Vérifie/installe **Git** (>= 2.34)
4. Vérifie la présence d'une **clé SSH**
5. Vérifie la présence de **terraform.tfvars**
6. Lance **terraform init** si nécessaire

Si tout est déjà en place, le script affiche "Ton environnement est déjà prêt." et ne modifie rien.

## Utilisation rapide avec infra.sh

Le script `infra.sh` centralise toutes les opérations d'infrastructure.

```bash
# Afficher l'aide
./infra.sh help

# Lister les environnements disponibles
./infra.sh envs
```

### Déploiement

```bash
# Initialiser Terraform
./infra.sh init

# Prévisualiser les changements
./infra.sh plan

# Déployer l'infrastructure
./infra.sh deploy

# Déployer sans confirmation
./infra.sh deploy -a
```

### Accès SSH

```bash
# Connexion SSH (ubuntu par défaut)
./infra.sh ssh

# Connexion avec un autre utilisateur
./infra.sh ssh -u root
```

### Destruction

```bash
# Détruire l'infrastructure (avec confirmation)
./infra.sh destroy

# Détruire sans confirmation
./infra.sh destroy -a
```

### Autres commandes

```bash
# Afficher les outputs Terraform (IP, commande SSH...)
./infra.sh output

# Afficher l'état des ressources déployées
./infra.sh status
```

### Cibler un autre environnement

Toutes les commandes acceptent `-e <env>` pour cibler un environnement spécifique :

```bash
./infra.sh deploy -e sandbox-sbg5
./infra.sh ssh -e sandbox-sbg5 -u root
./infra.sh destroy -e sandbox-sbg5 -a
```

## Configuration

Copier et remplir le fichier de variables dans l'environnement cible :

```bash
cd envs/sandbox-sbg5
cp terraform.tfvars.dist terraform.tfvars
# Éditer terraform.tfvars avec vos valeurs
```

> Attendre 3-5 minutes après le deploy pour que cloud-init termine l'installation de Nginx.

## Vérification post-déploiement

```bash
# IP publique
./infra.sh output

# Test HTTPS
curl -k https://$(cd envs/sandbox-sbg5 && terraform output -raw vm_public_ip)

# État du cloud-init
./infra.sh ssh
# puis sur la VM : sudo cloud-init status
```

## Dépannage

| Erreur | Solution |
|--------|----------|
| `No suitable endpoint for network service in SBG region` | La région doit être `SBG5` (pas `SBG`) |
| `ExternalGatewayForFloatingIPNotFound` | Lancer `./infra.sh destroy` puis `./infra.sh deploy` |
| `RouterInUse` lors du destroy | `./infra.sh destroy` détache automatiquement l'interface routeur |
| Nginx ne répond pas | Vérifier `sudo cloud-init status` via `./infra.sh ssh` |
