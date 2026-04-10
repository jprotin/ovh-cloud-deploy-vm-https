# OVHcloud Public Cloud — Landing Zone IaC
## Documentation Technique Complète

> **Auteur** : Johan Protin  
> **Région** : SBG5 (Strasbourg)  
> **Stack** : Terraform >= 1.5 · OVHcloud Public Cloud · Ubuntu 24.04  
> **Date** : Avril 2026

---

## Table des matières

1. [Installation des outils](#1-installation-des-outils)
2. [Script d'initialisation du projet](#2-script-dinitialisation-du-projet)
3. [Introduction](#3-introduction)
4. [Architecture](#4-architecture)
5. [Structure du projet](#5-structure-du-projet)
6. [Modules Terraform](#6-modules-terraform)
7. [Prérequis et configuration](#7-prérequis-et-configuration)
8. [Script infra.sh](#8-script-infrash)
9. [Procédures de déploiement](#9-procédures-de-déploiement)
10. [Destruction de l'infrastructure](#10-destruction-de-linfrastructure)
11. [Provisionning cloud-init](#11-provisionning-cloud-init)
12. [Dépannage](#12-dépannage)
13. [Estimation des coûts](#13-estimation-des-coûts)
14. [Évolutions possibles](#14-évolutions-possibles)

---

## 1. Installation des outils

Avant toute chose, les outils suivants doivent être installés sur ta machine locale.

### 1.1 Terraform

```bash
# Debian/Ubuntu — via le dépôt officiel HashiCorp
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform

# Vérification
terraform -version
# Terraform v1.x.x
```

### 1.2 Client OpenStack (python-openstackclient)

Le client OpenStack est nécessaire pour diagnostiquer les ressources, vérifier les endpoints API et exécuter la destruction propre via `infra.sh destroy`.

```bash
# Installation via apt (méthode recommandée sur Debian/Ubuntu)
sudo apt install -y python3-openstackclient

# Vérification
openstack --version
# openstack 6.x.x
```

> Ne pas utiliser `pip install` directement sur les distributions récentes (Ubuntu 22.04+, Debian 12+) car l'environnement Python est géré par le système (`PEP 668`). Utiliser `apt` ou un environnement virtuel.

Si tu préfères un environnement virtuel Python :

```bash
# Alternative via venv
python3 -m venv ~/.venv/openstack
source ~/.venv/openstack/bin/activate
pip install python-openstackclient
```

### 1.3 Clé SSH

Une paire de clés SSH est nécessaire pour accéder à la VM après déploiement.

```bash
# Vérifier si une clé existe déjà
ls -la ~/.ssh/id_rsa.pub

# Si absente, générer une nouvelle clé (ED25519 recommandé)
ssh-keygen -t ed25519 -C "terraform-ovh"

# Ou en RSA 4096
ssh-keygen -t rsa -b 4096 -C "terraform-ovh"

# Afficher la clé publique (à copier dans terraform.tfvars)
cat ~/.ssh/id_rsa.pub
```

> La fonction `file()` de Terraform ne résout pas le `~` (tilde). Utiliser le **contenu direct** de la clé dans la variable `ssh_public_key` du `terraform.tfvars` plutôt que le chemin.

### 1.4 Git

```bash
sudo apt install -y git

# Configuration minimale
git config --global user.name "Johan Protin"
git config --global user.email "johan.protin@monemail.com"
```

### 1.5 Récapitulatif des versions validées

| Outil | Version testée | Commande de vérification |
|---|---|---|
| Terraform | >= 1.5.0 | `terraform -version` |
| python-openstackclient | >= 6.0 | `openstack --version` |
| Python | >= 3.10 | `python3 --version` |
| Git | >= 2.34 | `git --version` |

### 1.6 Configuration du client OpenStack

Après avoir téléchargé le fichier `openrc.sh` depuis l'espace client OVHcloud, modifier la région et sourcer le fichier avant toute commande `openstack` :

```bash
# Modifier la région (SBG → SBG5)
sed -i 's/OS_REGION_NAME="SBG"/OS_REGION_NAME="SBG5"/' openrc.sh

# Sourcer le fichier (demande le mot de passe OpenStack)
source openrc.sh

# Vérifier la connexion
openstack token issue

# Vérifier les endpoints réseau disponibles
openstack catalog list | grep neutron
```

---

## 2. Script d'initialisation du projet

Le script `_init-project/setup.sh` automatise l'installation et la vérification de tous les prérequis nécessaires pour travailler sur le projet. Il peut être lancé à tout moment pour s'assurer que l'environnement de travail est prêt.

### 2.1 Utilisation

```bash
./_init-project/setup.sh
```

### 2.2 Ce que le script vérifie et installe

| Étape | Outil | Version min | Action si absent/obsolète |
|---|---|---|---|
| 1 | Terraform | >= 1.5.0 | Installation via le dépôt HashiCorp |
| 2 | python-openstackclient | >= 6.0.0 | Installation via `apt` |
| 3 | Git | >= 2.34.0 | Installation via `apt` |
| 4 | Clé SSH | — | Affiche les instructions de génération |
| 5 | terraform.tfvars | — | Affiche les instructions de création |
| 6 | terraform init | — | Lance `terraform init` dans l'environnement |

### 2.3 Comportement

- **Tout est prêt** : le script affiche "Ton environnement est déjà prêt." et ne modifie rien
- **Action(s) nécessaire(s)** : le script installe/met à jour les outils manquants et affiche le nombre d'actions effectuées
- Le script ne gère pas les credentials (terraform.tfvars, openrc.sh) — ces fichiers doivent être configurés manuellement

### 2.4 Exemple de sortie (environnement déjà prêt)

```
========================================
  Setup environnement de travail
  OVHcloud Landing Zone IaC
========================================

[INFO]    Vérification de Terraform (>= 1.5.0)...
[OK]      Terraform 1.14.8

[INFO]    Vérification du client OpenStack (>= 6.0.0)...
[OK]      python-openstackclient 6.6.0

[INFO]    Vérification de Git (>= 2.34.0)...
[OK]      Git 2.43.0

[INFO]    Vérification de la clé SSH...
[OK]      Clé SSH RSA présente

[INFO]    Vérification de terraform.tfvars...
[OK]      terraform.tfvars présent

[INFO]    Vérification de l'initialisation Terraform...
[OK]      Terraform déjà initialisé

----------------------------------------

  Ton environnement est déjà prêt.

----------------------------------------
```

---

## 3. Introduction

Ce document décrit l'architecture et les procédures de déploiement d'une landing zone sur OVHcloud Public Cloud via Terraform (Infrastructure as Code). L'objectif est de disposer d'un environnement cloud reproductible, versionné et entièrement automatisé.

**Objectif** : Déployer une VM Ubuntu 24.04 avec Nginx HTTPS sur OVHcloud Public Cloud SBG5, dans un réseau privé isolé, accessible via IP flottante, en moins de 5 minutes.

### Périmètre

| Composant | Technologie | Détail |
|---|---|---|
| IaC | Terraform >= 1.5 | Providers OVH + OpenStack |
| Cloud | OVHcloud Public Cloud | Région SBG5 (Strasbourg) |
| Compute | Instance d2-2 | 1 vCPU / 2 GB RAM / 25 GB |
| OS | Ubuntu 24.04 LTS | Image officielle OVHcloud |
| Web | Nginx + TLS | Certificat auto-signé RSA 2048 |
| Provisionning | cloud-init | Installation automatique au boot |

---

## 4. Architecture

### Vue d'ensemble

```
OVHcloud Public Cloud - Région SBG5
│
├── Réseau
│   ├── Ext-Net (581fad02)          [Réseau public OVHcloud - Read Only]
│   ├── landing-zone-demo-network   [10.0.1.0/24 - Réseau privé]
│   ├── landing-zone-demo-router    [Gateway vers Ext-Net, SNAT auto]
│   └── IP flottante                [IP publique assignée dynamiquement]
│
├── Sécurité
│   ├── landing-zone-demo-sg
│   │   ├── SSH  (22)   ingress  admin_cidr/32
│   │   ├── HTTP (80)   ingress  0.0.0.0/0  → redirect HTTPS
│   │   ├── HTTPS(443)  ingress  0.0.0.0/0
│   │   └── ICMP        ingress  0.0.0.0/0
│   └── landing-zone-demo-keypair   [Clé SSH RSA]
│
└── Compute
    └── landing-zone-demo-vm
        ├── Flavor   : d2-2 (1 vCPU / 2 GB / 25 GB)
        ├── OS       : Ubuntu 24.04 LTS
        ├── Nginx    : HTTP(301) → HTTPS(443)
        └── Init     : cloud-init automatique
```

### Isolation des projets

Chaque projet OVHcloud Public Cloud est un **tenant OpenStack indépendant**. Les ressources réseau créées dans ce projet sont totalement étanches aux autres projets du même compte OVHcloud.

```
Ton compte OVHcloud
│
├── Projet Public Cloud "Client A"  ─┐
├── Projet Public Cloud "Client B"  ─┤─ Tenants isolés — aucune visibilité croisée
└── Projet Public Cloud "Sandbox"   ─┘  ← on travaille ici
```

### Nomenclature des flavors OVHcloud

| Préfixe | Famille | Usage |
|---|---|---|
| `b` | Balanced | Usage général, équilibré CPU/RAM |
| `c` | CPU | Calcul intensif, CPU optimisé |
| `r` | RAM | Mémoire optimisée (bases de données) |
| `d` | Discovery | Entrée de gamme, test/dev ← **choix sandbox** |
| `i` | IOPS | Stockage haute performance |
| `win-` | Windows | Flavors avec licence Windows incluse |

> Le suffixe `-flex` indique un disque système réduit à 50 GB, plus adapté aux snapshots et migrations.

---

## 5. Structure du projet

Le projet suit une architecture modulaire mono-repo avec séparation entre modules réutilisables et environnements.

```
.
├── modules/                          # Modules Terraform réutilisables
│   ├── network/                      # Réseau, routeur, SG, keypair
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   ├── compute/                      # VM, port, floating IP
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   ├── mks/                          # Kubernetes managé (futur)
│   │   └── .gitkeep
│   └── dbaas/                        # Bases de données managées (futur)
│       └── .gitkeep
│
├── envs/                             # Environnements de déploiement
│   └── sandbox-sbg5/                 # Sandbox OVHcloud SBG5
│       ├── main.tf                   # Assemblage des modules
│       ├── variables.tf              # Variables d'entrée
│       ├── outputs.tf                # Sorties (IP, SSH...)
│       ├── providers.tf              # Config providers OVH + OpenStack
│       ├── versions.tf               # Contraintes de versions
│       ├── terraform.tfvars          # Valeurs (non versionné)
│       ├── terraform.tfvars.dist     # Template de variables
│       └── cloud-init.yaml           # Provisionning VM
│
├── _init-project/
│   └── setup.sh                      # Installation automatique des prérequis
├── infra.sh                          # CLI de gestion unifiée
├── destroy.sh                        # Script de destruction legacy
├── README.md                         # Documentation rapide
└── DOCUMENTATION.md                  # Documentation technique complète
```

### Providers utilisés

| Provider | Version | Usage |
|---|---|---|
| `ovh/ovh` | `~> 0.46` | Gestion des ressources OVHcloud (API OVH) |
| `openstack/openstack` | `~> 2.1` | Gestion des ressources compute/réseau (API OpenStack) |

### Fichiers de l'environnement `sandbox-sbg5`

#### `versions.tf`

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "~> 0.46"
    }
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 2.1"
    }
  }
}
```

#### `providers.tf`

```hcl
provider "ovh" {
  endpoint           = "ovh-eu"
  application_key    = var.ovh_application_key
  application_secret = var.ovh_application_secret
  consumer_key       = var.ovh_consumer_key
}

provider "openstack" {
  auth_url      = var.os_auth_url
  tenant_id     = var.os_tenant_id
  tenant_name   = var.os_tenant_name
  user_name     = var.os_username
  password      = var.os_password
  region        = var.os_region
  endpoint_type = "public"
}
```

#### `variables.tf`

```hcl
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
  description = "CIDR autorisé en SSH (ex: 90.x.x.x/32)"
}
```

#### `main.tf` — Assemblage des modules

```hcl
# Ext-Net (réseau externe OVHcloud)
data "openstack_networking_network_v2" "ext_net" {
  network_id = "581fad02-158d-4dc6-81f0-c1ec2794bbec"
  region     = var.os_region
}

# Module réseau
module "network" {
  source = "../../modules/network"

  project_name   = var.project_name
  region         = var.os_region
  subnet_cidr    = "10.0.1.0/24"
  admin_cidr     = var.admin_cidr
  ssh_public_key = var.ssh_public_key
  ext_net_id     = data.openstack_networking_network_v2.ext_net.id
}

# Module compute (VM)
module "vm" {
  source = "../../modules/compute"

  project_name = var.project_name
  region       = var.os_region
  network_id   = module.network.network_id
  subnet_id    = module.network.subnet_id
  secgroup_id  = module.network.secgroup_id
  keypair_name = module.network.keypair_name
  image_name   = "Ubuntu 24.04"
  flavor_name  = "d2-2"
  user_data    = file("${path.module}/cloud-init.yaml")

  metadata = {
    project     = var.project_name
    environment = "sandbox"
    managed_by  = "terraform"
  }

  depends_on = [module.network]
}
```

#### `outputs.tf`

```hcl
output "vm_name" {
  description = "Nom de la VM"
  value       = module.vm.vm_name
}

output "vm_private_ip" {
  description = "IP privée de la VM"
  value       = module.vm.private_ip
}

output "vm_public_ip" {
  description = "IP publique flottante"
  value       = module.vm.public_ip
}

output "ssh_command" {
  description = "Commande SSH pour se connecter"
  value       = "ssh ubuntu@${module.vm.public_ip}"
}
```

#### `.gitignore`

```
terraform.tfvars
*.tfstate
*.tfstate.backup
.terraform/
.terraform.lock.hcl
openrc.sh
```

---

## 6. Modules Terraform

### 6.1 Module `network`

Le module réseau crée l'ensemble de l'infrastructure réseau nécessaire à un environnement OVHcloud.

**Ressources créées :**

| Ressource | Description |
|---|---|
| `openstack_networking_network_v2` | Réseau privé |
| `openstack_networking_subnet_v2` | Subnet avec DNS |
| `openstack_networking_router_v2` | Routeur vers Ext-Net |
| `openstack_networking_router_interface_v2` | Interface routeur/subnet |
| `openstack_networking_secgroup_v2` | Security group |
| `openstack_networking_secgroup_rule_v2` | Règles SSH, HTTP, HTTPS, ICMP |
| `openstack_compute_keypair_v2` | Keypair SSH |

**Variables d'entrée :**

| Variable | Type | Défaut | Description |
|---|---|---|---|
| `project_name` | `string` | — | Préfixe des ressources |
| `region` | `string` | — | Région OpenStack |
| `subnet_cidr` | `string` | `10.0.1.0/24` | CIDR du subnet privé |
| `dns_nameservers` | `list(string)` | `["213.186.33.99", "8.8.8.8"]` | Serveurs DNS |
| `ext_net_id` | `string` | — | ID du réseau externe (Ext-Net) |
| `admin_cidr` | `string` | — | CIDR autorisé en SSH |
| `ssh_public_key` | `string` | — | Contenu de la clé publique SSH |

**Outputs :**

| Output | Description |
|---|---|
| `network_id` | ID du réseau privé |
| `subnet_id` | ID du subnet |
| `secgroup_id` | ID du security group |
| `keypair_name` | Nom de la keypair SSH |
| `router_id` | ID du routeur |

### 6.2 Module `compute`

Le module compute déploie une VM générique avec port réseau et IP flottante.

**Ressources créées :**

| Ressource | Description |
|---|---|
| `openstack_networking_port_v2` | Port réseau sur le réseau privé |
| `openstack_networking_floatingip_v2` | IP flottante publique |
| `openstack_compute_instance_v2` | Instance VM |
| `openstack_networking_floatingip_associate_v2` | Association IP flottante/port |

**Data sources :**

| Data source | Description |
|---|---|
| `openstack_images_image_v2` | Résolution de l'image OS par nom |
| `openstack_compute_flavor_v2` | Résolution du flavor par nom |

**Variables d'entrée :**

| Variable | Type | Défaut | Description |
|---|---|---|---|
| `project_name` | `string` | — | Préfixe des ressources |
| `region` | `string` | — | Région OpenStack |
| `network_id` | `string` | — | ID du réseau privé |
| `subnet_id` | `string` | — | ID du subnet |
| `secgroup_id` | `string` | — | ID du security group |
| `keypair_name` | `string` | — | Nom de la keypair SSH |
| `image_name` | `string` | `Ubuntu 24.04` | Nom de l'image OS |
| `flavor_name` | `string` | `d2-2` | Nom du flavor |
| `user_data` | `string` | `null` | Contenu cloud-init |
| `metadata` | `map(string)` | `{}` | Metadata de l'instance |

**Outputs :**

| Output | Description |
|---|---|
| `vm_name` | Nom de la VM |
| `vm_id` | ID de la VM |
| `private_ip` | IP privée |
| `public_ip` | IP publique flottante |

### 6.3 Modules futurs

| Module | Statut | Description |
|---|---|---|
| `mks` | Placeholder | OVHcloud Managed Kubernetes Service |
| `dbaas` | Placeholder | Bases de données managées OVHcloud |

Ces modules seront implémentés selon les besoins. La structure est prête à les accueillir.

---

## 7. Prérequis et configuration

### 7.1 Clés API OVHcloud

Se rendre sur https://www.ovh.com/auth/api/createToken et créer un token avec les droits :

- `GET /cloud/*`
- `POST /cloud/*`
- `PUT /cloud/*`
- `DELETE /cloud/*`

Le token génère trois valeurs : `application_key`, `application_secret`, `consumer_key`.

### 7.2 Utilisateur OpenStack

Dans l'espace client OVHcloud : **Public Cloud → Project Management → Users & Roles**

1. Créer un utilisateur avec le rôle **Administrator**
2. Copier le mot de passe affiché **une seule fois**
3. Télécharger le fichier `openrc.sh` (région SBG)
4. Modifier `OS_REGION_NAME=SBG` en `OS_REGION_NAME=SBG5` dans le fichier

> **Point critique** : OVHcloud expose les services réseau (Neutron) sous l'identifiant `SBG5` dans le catalog OpenStack et non `SBG`. Cette distinction est critique pour que Terraform trouve les bons endpoints API.

### 7.3 Endpoints API OVHcloud SBG5

| Service | Endpoint public |
|---|---|
| neutron (réseau) | `https://network.compute.sbg5.cloud.ovh.net/` |
| nova (compute) | `https://compute.sbg5.cloud.ovh.net/` |
| cinder (volumes) | `https://volume.compute.sbg5.cloud.ovh.net/` |
| glance (images) | `https://image.compute.sbg5.cloud.ovh.net/` |
| swift (object) | `https://storage.sbg.cloud.ovh.net/` |

### 7.4 Fichier terraform.tfvars

```hcl
# OVH API
ovh_application_key    = "XXXXXXXXXXXX"
ovh_application_secret = "XXXXXXXXXXXX"
ovh_consumer_key       = "XXXXXXXXXXXX"

# OpenStack
os_tenant_id   = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
os_tenant_name = "xxxxxxxxxxxxxxxxx"
os_username    = "user-xxxxxxxxxx"
os_password    = "XXXXXXXXXXXX"
os_region      = "SBG5"

# Projet
project_name = "landing-zone-demo"
admin_cidr   = "XX.XX.XX.XX/32"   # curl ifconfig.me

# Clé SSH (contenu direct, pas le chemin du fichier)
ssh_public_key = "ssh-rsa AAAA... user@host"
```

---

## 8. Script infra.sh

Le script `infra.sh` à la racine du repo fournit une CLI unifiée pour toutes les opérations d'infrastructure. Il remplace les appels manuels à `terraform` et `destroy.sh`.

### 8.1 Commandes disponibles

| Commande | Options | Description |
|---|---|---|
| `init` | `-e env` | Initialise Terraform (`terraform init`) |
| `plan` | `-e env` | Prévisualise les changements (`terraform plan`) |
| `deploy` | `-e env`, `-a` | Déploie l'infrastructure (`terraform apply`) |
| `destroy` | `-e env`, `-a` | Détache le routeur OVH puis détruit (`terraform destroy`) |
| `ssh` | `-e env`, `-u user` | Connexion SSH à la VM |
| `output` | `-e env` | Affiche les outputs Terraform |
| `status` | `-e env` | Affiche l'état des ressources |
| `envs` | — | Liste les environnements disponibles |
| `help` | — | Affiche l'aide |

### 8.2 Options globales

| Option | Description | Défaut |
|---|---|---|
| `-e`, `--env` | Environnement cible | `sandbox-sbg5` |
| `-u`, `--user` | Utilisateur SSH | `ubuntu` |
| `-a`, `--auto-approve` | Applique sans confirmation (deploy/destroy) | désactivé |
| `-h`, `--help` | Affiche l'aide | — |

### 8.3 Exemples d'utilisation

```bash
# Workflow complet de déploiement
./infra.sh init
./infra.sh plan
./infra.sh deploy

# Déploiement rapide sans confirmation
./infra.sh deploy -a

# Connexion SSH
./infra.sh ssh
./infra.sh ssh -u root

# Vérifier l'état
./infra.sh output
./infra.sh status

# Destruction propre
./infra.sh destroy

# Cibler un autre environnement
./infra.sh deploy -e mon-autre-env
./infra.sh ssh -e mon-autre-env -u admin
```

### 8.4 Fonctionnement interne

- **Auto-init** : la commande `deploy` lance automatiquement `terraform init` si le répertoire `.terraform` n'existe pas encore
- **Détachement routeur** : la commande `destroy` détache automatiquement l'interface routeur du subnet avant le `terraform destroy` (nécessaire sur OVHcloud)
- **Détection d'environnement** : le script vérifie que l'environnement cible existe dans `envs/` et liste les environnements disponibles en cas d'erreur
- **Résolution d'IP** : la commande `ssh` récupère automatiquement l'IP publique depuis les outputs Terraform

---

## 9. Procédures de déploiement

### 9.1 Premier déploiement

```bash
# Avec infra.sh (recommandé)
./infra.sh init
./infra.sh plan
./infra.sh deploy

# Ou manuellement
cd envs/sandbox-sbg5
terraform init
terraform validate
terraform plan
terraform apply
```

Après le deploy, les outputs sont affichés automatiquement :

```
ssh_command   = "ssh ubuntu@XX.XX.XX.XX"
vm_name       = "landing-zone-demo-vm"
vm_private_ip = "10.0.1.X"
vm_public_ip  = "XX.XX.XX.XX"
```

> Attendre 3 à 5 minutes pour que cloud-init termine l'installation de Nginx.

### 9.2 Vérification post-déploiement

```bash
# Connexion SSH
./infra.sh ssh

# Sur la VM :
sudo cloud-init status
# Résultat attendu : status: done

# Depuis la machine locale :
# Test HTTP (doit retourner 301 → HTTPS)
curl -I http://<IP>

# Test HTTPS (certificat auto-signé, -k ignore l'avertissement)
curl -k https://<IP>
```

### 9.3 Vérification des ressources OVHcloud via CLI

```bash
source openrc.sh
export OS_REGION_NAME=SBG5

openstack network list          # Vérifie le réseau privé et Ext-Net
openstack router list           # Vérifie le routeur (ACTIVE/UP)
openstack security group list   # Vérifie le security group
openstack keypair list          # Vérifie la clé SSH
openstack server list           # Vérifie la VM (ACTIVE)
openstack port list             # Vérifie les ports réseau
```

---

## 10. Destruction de l'infrastructure

### 10.1 Pourquoi un traitement spécial ?

OVHcloud crée automatiquement des **interfaces routeur supplémentaires** (ports SNAT distribués) lors de l'attachement du routeur au subnet privé. Ces ports ne sont pas gérés par Terraform et bloquent la suppression du subnet et du routeur lors d'un `terraform destroy` standard, avec l'erreur :

```
Error: RouterInUse — Router still has ports (409)
Error: timeout waiting for subnet to become DELETED
```

### 10.2 Destruction avec infra.sh (recommandé)

La commande `destroy` gère automatiquement le détachement de l'interface routeur :

```bash
# Avec confirmation
./infra.sh destroy

# Sans confirmation (sandbox uniquement)
./infra.sh destroy -a

# Cibler un environnement
./infra.sh destroy -e sandbox-sbg5
```

### 10.3 Destruction manuelle

Si nécessaire, les étapes manuelles sont :

```bash
# 1. Détacher l'interface du routeur
SUBNET_ID=$(openstack subnet list | grep landing-zone-demo | awk '{print $2}')
openstack router remove subnet landing-zone-demo-router $SUBNET_ID

# 2. Lancer terraform destroy
cd envs/sandbox-sbg5
terraform destroy
```

---

## 11. Provisionning cloud-init

### 11.1 Fonctionnement

Le fichier `cloud-init.yaml` (dans `envs/sandbox-sbg5/`) est injecté dans la VM via le paramètre `user_data` du module `compute`. OVHcloud l'exécute automatiquement au premier boot.

### 11.2 Séquence d'exécution

| Ordre | Action | Détail |
|---|---|---|
| 1 | `write_files` | Écrit `index.html` et la config Nginx avant installation |
| 2 | `apt-get update` (retry) | Boucle jusqu'à disponibilité réseau (`until`) |
| 3 | `apt-get install` | Installation `nginx` et `openssl` |
| 4 | `openssl req` | Génération certificat auto-signé RSA 2048 (365j) |
| 5 | `ln -s` (symlink) | Active la config Nginx dans `sites-enabled` |
| 6 | `systemctl restart` | Démarre Nginx avec la nouvelle config |

### 11.3 Fichier cloud-init.yaml complet

```yaml
#cloud-config
write_files:
  - path: /var/www/html/index.html
    owner: www-data:www-data
    permissions: '0644'
    content: |
      <!DOCTYPE html>
      <html lang="fr">
      <head>
        <meta charset="UTF-8">
        <title>Landing Zone - OVHcloud SBG5</title>
        <style>
          body {
            font-family: sans-serif;
            background: #0f1923;
            color: #fff;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
          }
          .card {
            background: #1a2a3a;
            border: 1px solid #00a8e0;
            border-radius: 12px;
            padding: 40px 60px;
            text-align: center;
            box-shadow: 0 0 30px rgba(0,168,224,0.2);
          }
          h1 { color: #00a8e0; margin-bottom: 8px; }
          p  { color: #aaa; margin: 6px 0; }
          .badge {
            display: inline-block;
            margin-top: 20px;
            background: #00a8e0;
            color: #000;
            padding: 4px 14px;
            border-radius: 20px;
            font-size: 0.85em;
            font-weight: bold;
          }
        </style>
      </head>
      <body>
        <div class="card">
          <h1>Landing Zone IaC</h1>
          <p>OVHcloud Public Cloud — Région <strong>SBG5</strong></p>
          <p>Infrastructure déployée avec <strong>Terraform</strong></p>
          <p>VM : <strong>landing-zone-demo-vm</strong></p>
          <div class="badge">Opérationnelle</div>
        </div>
      </body>
      </html>

  - path: /etc/nginx/sites-available/default
    permissions: '0644'
    content: |
      server {
          listen 80;
          server_name _;
          return 301 https://$host$request_uri;
      }
      server {
          listen 443 ssl;
          server_name _;
          ssl_certificate     /etc/ssl/certs/nginx-selfsigned.crt;
          ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;
          ssl_protocols       TLSv1.2 TLSv1.3;
          ssl_ciphers         HIGH:!aNULL:!MD5;
          root /var/www/html;
          index index.html;
          location / {
              try_files $uri $uri/ =404;
          }
      }

runcmd:
  # Attend que le réseau soit disponible avant d'installer
  - until apt-get update; do echo "Réseau pas encore disponible, retry..."; sleep 10; done
  # Installe Nginx et OpenSSL
  - apt-get install -y nginx openssl
  # Génère le certificat auto-signé (365 jours)
  - openssl req -x509 -nodes -days 365
      -newkey rsa:2048
      -keyout /etc/ssl/private/nginx-selfsigned.key
      -out /etc/ssl/certs/nginx-selfsigned.crt
      -subj "/C=FR/ST=Alsace/L=Strasbourg/O=Nantares/CN=landing-zone"
  # Active la config Nginx (symlink obligatoire sur Ubuntu 24.04)
  - ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
  # Démarre Nginx
  - systemctl enable nginx
  - systemctl restart nginx
```

> **Point critique** : Sur Ubuntu 24.04, le fichier de configuration Nginx doit être activé via un symlink de `sites-available` vers `sites-enabled`. Sans cette étape, Nginx démarre sans écouter sur les ports 80 et 443.

---

## 12. Dépannage

### Erreurs Terraform

| Erreur | Cause | Solution |
|---|---|---|
| `No suitable endpoint for network service in SBG` | Mauvais nom de région | Utiliser `SBG5` dans `terraform.tfvars` |
| `ExternalGatewayForFloatingIPNotFound` | Interface routeur non attachée | `./infra.sh destroy` puis `./infra.sh deploy` |
| `RouterInUse (409)` lors du destroy | Ports OVHcloud résiduels | Utiliser `./infra.sh destroy` |
| `SecurityGroupRuleExists (409)` | OVHcloud crée une règle egress auto | Supprimer la ressource `egress_all` du module |
| `failed to generate fingerprint` | Mauvaise lecture de la clé SSH | Utiliser `ssh_public_key` avec le contenu direct |
| `PolicyNotAuthorized` sur `enable_snat` | Droit réservé aux admins OVHcloud | Supprimer `enable_snat` du routeur |

### Erreurs Nginx / cloud-init

| Symptôme | Cause | Solution |
|---|---|---|
| `curl: (7) Failed to connect port 443` | Nginx n'écoute pas | Vérifier le symlink `sites-enabled` |
| `Unit nginx.service could not be found` | cloud-init a échoué | Installer Nginx manuellement |
| `Temporary failure resolving archive.ubuntu.com` | Réseau pas disponible au boot | Le `until apt-get update` gère ce cas |
| `sites-enabled` vide | Symlink non créé | `sudo ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default` |

### Commandes de diagnostic

```bash
# Connexion rapide
./infra.sh ssh

# État du cloud-init
sudo cloud-init status
sudo cat /var/log/cloud-init-output.log

# État de Nginx
sudo systemctl status nginx
sudo nginx -t
sudo ss -tlnp | grep -E '80|443'
sudo ls -la /etc/nginx/sites-enabled/

# État du routeur OVHcloud (depuis la machine locale)
source openrc.sh
openstack router show landing-zone-demo-router -f json | python3 -m json.tool

# Ports résiduels
openstack port list
```

---

## 13. Estimation des coûts

La facturation OVHcloud Public Cloud est **à l'heure**, convertible en mensuel sur la base de 730h/mois.

| Ressource | Prix/heure (indicatif) | Estimation/mois |
|---|---|---|
| Instance `d2-2` (1 vCPU / 2 GB / 25 GB) | ~0,003 €/h | ~2,20 € HT |
| IP flottante publique | ~0,004 €/h | ~2,90 € HT |
| **Total** | | **~5,10 € HT/mois** |

> La VM est facturée même si elle est éteinte. Pour stopper la facturation, supprimer l'instance via `./infra.sh destroy`. Les tarifs sont susceptibles d'évoluer suite aux hausses annoncées par OVHcloud début 2026 (+9 à +11% sur le Public Cloud).

---

## 14. Évolutions possibles

| Évolution | Description | Complexité |
|---|---|---|
| **Backend S3 OVHcloud** | Stocker le tfstate dans un bucket S3 OVHcloud pour le travail en équipe | Faible |
| **Ansible** | Remplacer cloud-init par un provisionning Ansible plus avancé et idempotent | Moyenne |
| **Multi-VM + Load Balancer** | Déployer plusieurs instances avec un Octavia LB en frontal | Élevée |
| **DNS + Let's Encrypt** | Pointer un domaine vers la VM et générer un certificat SSL valide | Faible |
| **Volumes block Cinder** | Ajouter un disque de données séparé attaché à la VM | Faible |
| **Module MKS** | Implémenter le module Kubernetes managé OVHcloud (`modules/mks/`) | Élevée |
| **Module DBaaS** | Implémenter le module bases de données managées (`modules/dbaas/`) | Moyenne |
| **Nouveaux environnements** | Ajouter d'autres envs dans `envs/` (prod, staging, autre région...) | Faible |

---

*Johan Protin — Avril 2026*
