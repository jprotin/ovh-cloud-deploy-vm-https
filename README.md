# 🚀 OVHcloud Public Cloud — Landing Zone IaC

Infrastructure as Code complète pour déployer une landing zone sur OVHcloud Public Cloud (région SBG5) avec Terraform.

## 📋 Table des matières

- [Architecture](#architecture)
- [Prérequis](#prérequis)
- [Structure du projet](#structure-du-projet)
- [Configuration](#configuration)
- [Déploiement](#déploiement)
- [Destruction](#destruction)
- [Accès à la VM](#accès-à-la-vm)
- [Dépannage](#dépannage)

---

## Architecture

```
OVHcloud Public Cloud - Région SBG5
│
├── 🌐 Réseau
│   ├── Réseau privé    : 10.0.1.0/24
│   ├── Routeur         : gateway → Ext-Net (SNAT activé)
│   └── IP flottante    : IP publique assignée dynamiquement
│
├── 🔒 Sécurité
│   └── Security Group
│       ├── SSH   (22)  → IP admin uniquement
│       ├── HTTP  (80)  → 0.0.0.0/0 (redirect HTTPS)
│       ├── HTTPS (443) → 0.0.0.0/0
│       └── ICMP        → 0.0.0.0/0
│
└── 💻 Compute
    └── VM Ubuntu 24.04
        ├── Flavor  : d2-2 (1 vCPU / 2 GB RAM / 25 GB)
        ├── Nginx   : HTTPS avec certificat auto-signé
        └── Provisionning : cloud-init automatique
```

---

## Prérequis

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5.0
- Un compte OVHcloud avec un projet Public Cloud
- Clés API OVHcloud ([générer ici](https://www.ovh.com/auth/api/createToken))
- Un utilisateur OpenStack créé dans le projet Public Cloud
- Une clé SSH générée localement

---

## Structure du projet

```
ovhcloud-landing-zone/
├── main.tf              # Ressources principales
├── variables.tf         # Déclaration des variables
├── terraform.tfvars     # Valeurs des variables (non versionné)
├── outputs.tf           # Outputs (IP, commande SSH...)
├── providers.tf         # Configuration des providers
├── versions.tf          # Contraintes de versions
├── cloud-init.yaml      # Provisionning automatique de la VM
├── destroy.sh           # Script de destruction propre
└── .gitignore
```

---

## Configuration

### 1. Clés API OVHcloud

Rends-toi sur [https://www.ovh.com/auth/api/createToken](https://www.ovh.com/auth/api/createToken) et crée un token avec les droits :
- `GET /cloud/*`
- `POST /cloud/*`
- `PUT /cloud/*`
- `DELETE /cloud/*`

### 2. Utilisateur OpenStack

Dans l'espace client OVHcloud :
1. **Public Cloud** → ton projet → **Project Management** → **Users & Roles**
2. Crée un utilisateur avec le rôle **Administrator**
3. Note le mot de passe affiché une seule fois
4. Télécharge le fichier `openrc.sh` (région SBG)
5. **Attention** : modifie `OS_REGION_NAME=SBG` en `OS_REGION_NAME=SBG5` dans le fichier

### 3. Fichier terraform.tfvars

Crée le fichier `terraform.tfvars` (jamais commité en Git) :

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
admin_cidr   = "XX.XX.XX.XX/32"   # Ton IP publique (curl ifconfig.me)

# Clé SSH publique
ssh_public_key = "ssh-rsa AAAA... user@host"
```

### 4. .gitignore

```
terraform.tfvars
*.tfstate
*.tfstate.backup
.terraform/
.terraform.lock.hcl
```

---

## Déploiement

```bash
# Initialisation
terraform init

# Validation
terraform validate

# Prévisualisation
terraform plan

# Déploiement
terraform apply
```

> ⚠️ Attends 3-5 minutes après l'apply pour que le cloud-init termine l'installation de Nginx.

### Vérification

```bash
# Test HTTP (doit rediriger vers HTTPS)
curl -I http://<IP_FLOTTANTE>

# Test HTTPS
curl -k https://<IP_FLOTTANTE>

# Connexion SSH
ssh ubuntu@<IP_FLOTTANTE>

# Vérification cloud-init
ssh ubuntu@<IP_FLOTTANTE> "sudo cloud-init status"
```

---

## Destruction

> ⚠️ OVHcloud crée automatiquement une interface routeur supplémentaire qui doit être détachée avant le destroy.

Utilise le script `destroy.sh` :

```bash
chmod +x destroy.sh
./destroy.sh
```

Le script effectue dans l'ordre :
1. Détache l'interface du routeur du subnet
2. Lance `terraform destroy`

---

## Accès à la VM

Les outputs Terraform fournissent directement la commande SSH :

```bash
terraform output ssh_command
# → ssh ubuntu@<IP>
```

L'utilisateur par défaut Ubuntu 24.04 sur OVHcloud est `ubuntu`.

---

## Dépannage

### Erreur : `No suitable endpoint for network service in SBG region`
→ La région dans `terraform.tfvars` doit être `SBG5` (et non `SBG`).

### Erreur : `ExternalGatewayForFloatingIPNotFound`
→ L'interface du routeur n'est pas attachée au subnet. Lance le `destroy.sh` puis `terraform apply`.

### Erreur : `RouterInUse` lors du destroy
→ Utilise le script `destroy.sh` qui détache d'abord l'interface manuellement.

### Nginx ne répond pas après l'apply
→ Le cloud-init est peut-être encore en cours. Vérifie avec :
```bash
ssh ubuntu@<IP> "sudo cloud-init status"
```
Si `status: done` mais Nginx ne répond pas, vérifie le symlink :
```bash
ssh ubuntu@<IP> "sudo ls /etc/nginx/sites-enabled/"
# Si vide :
ssh ubuntu@<IP> "sudo ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default && sudo systemctl restart nginx"
```

### Erreur : `failed to generate fingerprint` sur la keypair
→ Utilise la variable `ssh_public_key` avec le contenu direct de la clé (pas le chemin).
