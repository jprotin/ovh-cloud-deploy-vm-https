# OVHcloud Public Cloud — Landing Zone IaC
## Documentation Technique Complète

> **Auteur** : Johan Protin  
> **Région** : SBG5 (Strasbourg)  
> **Stack** : Terraform >= 1.5 · OVHcloud Public Cloud · Ubuntu 24.04  
> **Date** : Avril 2026

---

## Table des matières

1. [Installation des outils](#1-installation-des-outils)
2. [Introduction](#2-introduction)
3. [Architecture](#3-architecture)
4. [Structure du projet](#4-structure-du-projet)
5. [Prérequis et configuration](#5-prérequis-et-configuration)
6. [Procédures de déploiement](#6-procédures-de-déploiement)
7. [Destruction de l'infrastructure](#7-destruction-de-linfrastructure)
8. [Provisionning cloud-init](#8-provisionning-cloud-init)
9. [Dépannage](#9-dépannage)
10. [Estimation des coûts](#10-estimation-des-coûts)
11. [Évolutions possibles](#11-évolutions-possibles)

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

Le client OpenStack est nécessaire pour diagnostiquer les ressources, vérifier les endpoints API et exécuter le script `destroy.sh`.

```bash
# Installation via apt (méthode recommandée sur Debian/Ubuntu)
sudo apt install -y python3-openstackclient

# Vérification
openstack --version
# openstack 6.x.x
```

> ⚠️ **Ne pas utiliser `pip install` directement** sur les distributions récentes (Ubuntu 22.04+, Debian 12+) car l'environnement Python est géré par le système (`PEP 668`). Utiliser `apt` ou un environnement virtuel.

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

> ⚠️ La fonction `file()` de Terraform ne résout pas le `~` (tilde). Utiliser le **contenu direct** de la clé dans la variable `ssh_public_key` du `terraform.tfvars` plutôt que le chemin.

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

## 2. Introduction

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

## 2. Architecture

### Vue d'ensemble

```
OVHcloud Public Cloud - Région SBG5
│
├── 🌐 Réseau
│   ├── Ext-Net (581fad02)          [Réseau public OVHcloud - Read Only]
│   ├── landing-zone-demo-network   [10.0.1.0/24 - Réseau privé]
│   ├── landing-zone-demo-router    [Gateway vers Ext-Net, SNAT auto]
│   └── IP flottante                [IP publique assignée dynamiquement]
│
├── 🔒 Sécurité
│   ├── landing-zone-demo-sg
│   │   ├── SSH  (22)   ingress  admin_cidr/32
│   │   ├── HTTP (80)   ingress  0.0.0.0/0  → redirect HTTPS
│   │   ├── HTTPS(443)  ingress  0.0.0.0/0
│   │   └── ICMP        ingress  0.0.0.0/0
│   └── landing-zone-demo-keypair   [Clé SSH RSA]
│
└── 💻 Compute
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

## 3. Structure du projet

```
ovhcloud-landing-zone/
├── versions.tf          # Contraintes de versions Terraform et providers
├── providers.tf         # Configuration des providers OVH et OpenStack
├── variables.tf         # Déclaration de toutes les variables
├── terraform.tfvars     # Valeurs des variables (⚠️ non versionné en Git)
├── main.tf              # Toutes les ressources OVHcloud/OpenStack
├── outputs.tf           # IP publique, IP privée, commande SSH
├── cloud-init.yaml      # Provisionning automatique de la VM au boot
├── destroy.sh           # Script de destruction propre (détache routeur)
└── .gitignore
```

### Providers utilisés

| Provider | Version | Usage |
|---|---|---|
| `ovh/ovh` | `~> 0.46` | Gestion des ressources OVHcloud (API OVH) |
| `openstack/openstack` | `~> 2.1` | Gestion des ressources compute/réseau (API OpenStack) |

### `versions.tf`

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

### `providers.tf`

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

### `variables.tf`

```hcl
variable "ovh_application_key" {}
variable "ovh_application_secret" {}
variable "ovh_consumer_key" {}

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

variable "project_name" {
  default = "landing-zone-demo"
}

variable "admin_cidr" {
  description = "Ton IP publique autorisée en SSH (ex: 90.x.x.x/32)"
}

variable "ssh_public_key" {
  description = "Contenu de la clé publique SSH"
}
```

### `main.tf` — Contenu complet

```hcl
# -------------------------------------------------------
# Réseau privé
# -------------------------------------------------------
resource "openstack_networking_network_v2" "private_net" {
  name           = "${var.project_name}-network"
  admin_state_up = true
  region         = var.os_region
}

resource "openstack_networking_subnet_v2" "private_subnet" {
  name            = "${var.project_name}-subnet"
  network_id      = openstack_networking_network_v2.private_net.id
  cidr            = "10.0.1.0/24"
  ip_version      = 4
  dns_nameservers = ["213.186.33.99", "8.8.8.8"]
  region          = var.os_region
}

# -------------------------------------------------------
# Ext-Net (réseau public OVHcloud SBG5)
# -------------------------------------------------------
data "openstack_networking_network_v2" "ext_net" {
  network_id = "581fad02-158d-4dc6-81f0-c1ec2794bbec"
  region     = var.os_region
}

# -------------------------------------------------------
# Routeur
# -------------------------------------------------------
resource "openstack_networking_router_v2" "router" {
  name                = "${var.project_name}-router"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.ext_net.id
  region              = var.os_region
  # enable_snat non spécifié : OVHcloud l'active automatiquement
}

# -------------------------------------------------------
# Security Group
# -------------------------------------------------------
resource "openstack_networking_secgroup_v2" "sg_base" {
  name        = "${var.project_name}-sg"
  description = "Security group de base - Landing Zone"
  region      = var.os_region
}

resource "openstack_networking_secgroup_rule_v2" "ssh_in" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.admin_cidr
  security_group_id = openstack_networking_secgroup_v2.sg_base.id
  region            = var.os_region
}

resource "openstack_networking_secgroup_rule_v2" "icmp_in" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.sg_base.id
  region            = var.os_region
}

resource "openstack_networking_secgroup_rule_v2" "http_in" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.sg_base.id
  region            = var.os_region
}

resource "openstack_networking_secgroup_rule_v2" "https_in" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.sg_base.id
  region            = var.os_region
}

# -------------------------------------------------------
# Keypair SSH
# -------------------------------------------------------
resource "openstack_compute_keypair_v2" "keypair" {
  name       = "${var.project_name}-keypair"
  public_key = var.ssh_public_key
  region     = var.os_region
}

# -------------------------------------------------------
# Data sources : image et flavor
# -------------------------------------------------------
data "openstack_images_image_v2" "ubuntu" {
  name        = "Ubuntu 24.04"
  most_recent = true
  region      = var.os_region
}

data "openstack_compute_flavor_v2" "flavor" {
  name   = "d2-2"
  region = var.os_region
}

# -------------------------------------------------------
# IP flottante publique
# -------------------------------------------------------
resource "openstack_networking_floatingip_v2" "floating_ip" {
  pool   = "Ext-Net"
  region = var.os_region
}

# -------------------------------------------------------
# Port réseau sur le réseau privé
# -------------------------------------------------------
resource "openstack_networking_port_v2" "vm_port" {
  name               = "${var.project_name}-port"
  network_id         = openstack_networking_network_v2.private_net.id
  admin_state_up     = true
  security_group_ids = [openstack_networking_secgroup_v2.sg_base.id]
  region             = var.os_region

  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.private_subnet.id
  }
}

# -------------------------------------------------------
# Instance VM
# -------------------------------------------------------
resource "openstack_compute_instance_v2" "vm" {
  name      = "${var.project_name}-vm"
  image_id  = data.openstack_images_image_v2.ubuntu.id
  flavor_id = data.openstack_compute_flavor_v2.flavor.id
  key_pair  = openstack_compute_keypair_v2.keypair.name
  region    = var.os_region
  user_data = file("cloud-init.yaml")

  network {
    port = openstack_networking_port_v2.vm_port.id
  }

  metadata = {
    project     = var.project_name
    environment = "sandbox"
    managed_by  = "terraform"
  }
}

# -------------------------------------------------------
# Association IP flottante <-> VM
# -------------------------------------------------------
resource "openstack_networking_floatingip_associate_v2" "fip_assoc" {
  floating_ip = openstack_networking_floatingip_v2.floating_ip.address
  port_id     = openstack_networking_port_v2.vm_port.id
  region      = var.os_region

  depends_on = [
    openstack_networking_router_v2.router,
    openstack_compute_instance_v2.vm
  ]
}
```

### `outputs.tf`

```hcl
output "vm_name" {
  description = "Nom de la VM"
  value       = openstack_compute_instance_v2.vm.name
}

output "vm_private_ip" {
  description = "IP privée de la VM"
  value       = openstack_networking_port_v2.vm_port.all_fixed_ips[0]
}

output "vm_public_ip" {
  description = "IP publique flottante"
  value       = openstack_networking_floatingip_v2.floating_ip.address
}

output "ssh_command" {
  description = "Commande SSH pour se connecter"
  value       = "ssh ubuntu@${openstack_networking_floatingip_v2.floating_ip.address}"
}
```

### `.gitignore`

```
terraform.tfvars
*.tfstate
*.tfstate.backup
.terraform/
.terraform.lock.hcl
```

---

## 4. Prérequis et configuration

### 4.1 Clés API OVHcloud

Se rendre sur https://www.ovh.com/auth/api/createToken et créer un token avec les droits :

- `GET /cloud/*`
- `POST /cloud/*`
- `PUT /cloud/*`
- `DELETE /cloud/*`

Le token génère trois valeurs : `application_key`, `application_secret`, `consumer_key`.

### 4.2 Utilisateur OpenStack

Dans l'espace client OVHcloud : **Public Cloud → Project Management → Users & Roles**

1. Créer un utilisateur avec le rôle **Administrator**
2. Copier le mot de passe affiché **une seule fois**
3. Télécharger le fichier `openrc.sh` (région SBG)
4. Modifier `OS_REGION_NAME=SBG` en `OS_REGION_NAME=SBG5` dans le fichier

> ⚠️ **Point critique** : OVHcloud expose les services réseau (Neutron) sous l'identifiant `SBG5` dans le catalog OpenStack et non `SBG`. Cette distinction est critique pour que Terraform trouve les bons endpoints API.

### 4.3 Endpoints API OVHcloud SBG5

| Service | Endpoint public |
|---|---|
| neutron (réseau) | `https://network.compute.sbg5.cloud.ovh.net/` |
| nova (compute) | `https://compute.sbg5.cloud.ovh.net/` |
| cinder (volumes) | `https://volume.compute.sbg5.cloud.ovh.net/` |
| glance (images) | `https://image.compute.sbg5.cloud.ovh.net/` |
| swift (object) | `https://storage.sbg.cloud.ovh.net/` |

### 4.4 Fichier terraform.tfvars

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

## 5. Procédures de déploiement

### 5.1 Premier déploiement

```bash
# Initialisation des providers
terraform init

# Validation de la syntaxe
terraform validate

# Prévisualisation des ressources à créer
terraform plan

# Déploiement (confirmer avec 'yes')
terraform apply
```

Après l'apply, Terraform affiche les outputs :

```
ssh_command   = "ssh ubuntu@XX.XX.XX.XX"
vm_name       = "landing-zone-demo-vm"
vm_private_ip = "10.0.1.X"
vm_public_ip  = "XX.XX.XX.XX"
```

> ⏳ Attendre 3 à 5 minutes pour que cloud-init termine l'installation de Nginx.

### 5.2 Vérification post-déploiement

```bash
# Vérifier l'état du cloud-init
ssh ubuntu@<IP> "sudo cloud-init status"
# Résultat attendu : status: done

# Test HTTP (doit retourner 301 → HTTPS)
curl -I http://<IP>

# Test HTTPS (certificat auto-signé, -k ignore l'avertissement)
curl -k https://<IP>

# Test redirection complète HTTP → HTTPS
curl -Lk http://<IP>
```

### 5.3 Vérification des ressources OVHcloud via CLI

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

## 6. Destruction de l'infrastructure

### 6.1 Pourquoi un script dédié ?

OVHcloud crée automatiquement des **interfaces routeur supplémentaires** (ports SNAT distribués) lors de l'attachement du routeur au subnet privé. Ces ports ne sont pas gérés par Terraform et bloquent la suppression du subnet et du routeur lors d'un `terraform destroy` standard, avec l'erreur :

```
Error: RouterInUse — Router still has ports (409)
Error: timeout waiting for subnet to become DELETED
```

### 6.2 Script destroy.sh

```bash
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
```

```bash
# Utilisation
chmod +x destroy.sh
./destroy.sh

# Avec auto-approve (sandbox uniquement)
./destroy.sh -auto-approve
```

---

## 7. Provisionning cloud-init

### 7.1 Fonctionnement

Le fichier `cloud-init.yaml` est injecté dans la VM via le paramètre `user_data` de la ressource Terraform `openstack_compute_instance_v2`. OVHcloud l'exécute automatiquement au premier boot.

### 7.2 Séquence d'exécution

| Ordre | Action | Détail |
|---|---|---|
| 1 | `write_files` | Écrit `index.html` et la config Nginx avant installation |
| 2 | `apt-get update` (retry) | Boucle jusqu'à disponibilité réseau (`until`) |
| 3 | `apt-get install` | Installation `nginx` et `openssl` |
| 4 | `openssl req` | Génération certificat auto-signé RSA 2048 (365j) |
| 5 | `ln -s` (symlink) | Active la config Nginx dans `sites-enabled` |
| 6 | `systemctl restart` | Démarre Nginx avec la nouvelle config |

### 7.3 Fichier cloud-init.yaml complet

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
          <h1>🚀 Landing Zone IaC</h1>
          <p>OVHcloud Public Cloud — Région <strong>SBG5</strong></p>
          <p>Infrastructure déployée avec <strong>Terraform</strong></p>
          <p>VM : <strong>landing-zone-demo-vm</strong></p>
          <div class="badge">✅ Opérationnelle</div>
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

> ⚠️ **Point critique** : Sur Ubuntu 24.04, le fichier de configuration Nginx doit être activé via un symlink de `sites-available` vers `sites-enabled`. Sans cette étape, Nginx démarre sans écouter sur les ports 80 et 443.

---

## 8. Dépannage

### Erreurs Terraform

| Erreur | Cause | Solution |
|---|---|---|
| `No suitable endpoint for network service in SBG` | Mauvais nom de région | Utiliser `SBG5` dans `terraform.tfvars` |
| `ExternalGatewayForFloatingIPNotFound` | Interface routeur non attachée | Lancer `destroy.sh` puis `terraform apply` |
| `RouterInUse (409)` lors du destroy | Ports OVHcloud résiduels | Utiliser `destroy.sh` |
| `SecurityGroupRuleExists (409)` | OVHcloud crée une règle egress auto | Supprimer la ressource `egress_all` du `main.tf` |
| `failed to generate fingerprint` | Mauvaise lecture de la clé SSH | Utiliser `ssh_public_key` avec le contenu direct |
| `PolicyNotAuthorized` sur `enable_snat` | Droit réservé aux admins OVHcloud | Supprimer `enable_snat` du routeur |

### Erreurs Nginx / cloud-init

| Symptôme | Cause | Solution |
|---|---|---|
| `curl: (7) Failed to connect port 443` | Nginx n'écoute pas | Vérifier le symlink `sites-enabled` |
| `Unit nginx.service could not be found` | cloud-init a échoué | Installer Nginx manuellement et corriger le `cloud-init.yaml` |
| `Temporary failure resolving archive.ubuntu.com` | Réseau pas disponible au boot | Le `until apt-get update` dans `runcmd` gère ce cas |
| `sites-enabled` vide | Symlink non créé | `sudo ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default` |

### Commandes de diagnostic

```bash
# État du cloud-init
ssh ubuntu@<IP> "sudo cloud-init status"
ssh ubuntu@<IP> "sudo cat /var/log/cloud-init-output.log"

# État de Nginx
ssh ubuntu@<IP> "sudo systemctl status nginx"
ssh ubuntu@<IP> "sudo nginx -t"
ssh ubuntu@<IP> "sudo ss -tlnp | grep -E '80|443'"
ssh ubuntu@<IP> "sudo ls -la /etc/nginx/sites-enabled/"

# État du routeur OVHcloud
openstack router show landing-zone-demo-router -f json | python3 -m json.tool

# Ports résiduels
openstack port list
```

---

## 9. Estimation des coûts

La facturation OVHcloud Public Cloud est **à l'heure**, convertible en mensuel sur la base de 730h/mois.

| Ressource | Prix/heure (indicatif) | Estimation/mois |
|---|---|---|
| Instance `d2-2` (1 vCPU / 2 GB / 25 GB) | ~0,003 €/h | ~2,20 € HT |
| IP flottante publique | ~0,004 €/h | ~2,90 € HT |
| **Total** | | **~5,10 € HT/mois** |

> ⚠️ La VM est facturée même si elle est éteinte. Pour stopper la facturation, supprimer l'instance via `./destroy.sh`. Les tarifs sont susceptibles d'évoluer suite aux hausses annoncées par OVHcloud début 2026 (+9 à +11% sur le Public Cloud).

---

## 10. Évolutions possibles

| Évolution | Description | Complexité |
|---|---|---|
| **Backend S3 OVHcloud** | Stocker le tfstate dans un bucket S3 OVHcloud pour le travail en équipe | Faible |
| **Terraform modules** | Modulariser le code réseau/compute pour réutilisation sur d'autres projets | Moyenne |
| **Ansible** | Remplacer cloud-init par un provisionning Ansible plus avancé et idempotent | Moyenne |
| **Multi-VM + Load Balancer** | Déployer plusieurs instances avec un Octavia LB en frontal | Élevée |
| **DNS + Let's Encrypt** | Pointer un domaine vers la VM et générer un certificat SSL valide | Faible |
| **Volumes block Cinder** | Ajouter un disque de données séparé attaché à la VM | Faible |
| **Kubernetes (MKS)** | Migrer vers OVHcloud Managed Kubernetes Service | Élevée |

---

*Johan Protin — Avril 2026*
