# OVHcloud Public Cloud — Landing Zone IaC

## Documentation Technique Complète

> **Auteur** : Johan Protin
> **Stack** : Terraform >= 1.5 · OVHcloud Public Cloud · Ubuntu 24.04 · Kubernetes managé (MKS)
> **Date** : Avril 2026

---

## Table des matières

1. [Installation des outils](#1-installation-des-outils)
2. [Script d'initialisation du projet](#2-script-dinitialisation-du-projet)
3. [Introduction](#3-introduction)
4. [Vision fonctionnelle](#4-vision-fonctionnelle)
5. [Structure du projet](#5-structure-du-projet)
6. [Modules Terraform](#6-modules-terraform)
7. [Environnements et feature flags](#7-environnements-et-feature-flags)
8. [Prérequis et configuration](#8-prérequis-et-configuration)
9. [Script infra.sh](#9-script-infrash)
10. [Procédures de déploiement](#10-procédures-de-déploiement)
11. [Module MKS (Kubernetes managé)](#11-module-mks-kubernetes-managé)
12. [Démo Kubernetes multi-AZ](#12-démo-kubernetes-multi-az)
13. [Destruction de l'infrastructure](#13-destruction-de-linfrastructure)
14. [Provisionning cloud-init](#14-provisionning-cloud-init)
15. [Dépannage](#15-dépannage)
16. [Estimation des coûts](#16-estimation-des-coûts)
17. [Évolutions possibles](#17-évolutions-possibles)
18. [Décisions d'architecture (ADR)](#18-décisions-darchitecture-adr)

---

## 1. Installation des outils

### 1.1 Terraform

```bash
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform
terraform -version
```

### 1.2 Client OpenStack

```bash
sudo apt install -y python3-openstackclient
openstack --version
```

### 1.3 kubectl (pour MKS)

```bash
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update && sudo apt install -y kubectl
kubectl version --client
```

### 1.4 Clé SSH

```bash
ssh-keygen -t ed25519 -C "terraform-ovh"
cat ~/.ssh/id_ed25519.pub   # Contenu à coller dans terraform.tfvars
```

### 1.5 Récapitulatif des versions

| Outil                  | Version min | Vérification               |
| ---------------------- | ----------- | -------------------------- |
| Terraform              | >= 1.5.0    | `terraform -version`       |
| python-openstackclient | >= 6.0      | `openstack --version`      |
| kubectl                | >= 1.28     | `kubectl version --client` |
| Git                    | >= 2.34     | `git --version`            |
| jq                     | toute       | `jq --version`             |
| curl                   | toute       | `curl --version`           |

> Astuce : `./infra.sh doctor` vérifie tous les prérequis en une commande (sans installation).

---

## 2. Script d'initialisation du projet

Le script `_init-project/setup.sh` automatise l'installation des prérequis.

```bash
./_init-project/setup.sh
```

**Vérifications effectuées** (dans l'ordre) :

| Étape | Outil                  | Version min | Action si absent                             |
| ----- | ---------------------- | ----------- | -------------------------------------------- |
| 1     | Terraform              | >= 1.5.0    | Installation via dépôt HashiCorp             |
| 2     | python-openstackclient | >= 6.0.0    | Installation via `apt`                       |
| 3     | Git                    | >= 2.34.0   | Installation via `apt`                       |
| 4     | kubectl                | >= 1.28.0   | Installation via dépôt Kubernetes officiel   |
| 5     | jq                     | toute       | Installation via `apt`                       |
| 6     | curl                   | toute       | Installation via `apt`                       |
| 7     | Clé SSH                | —           | Affiche les instructions de génération       |
| 8     | terraform.tfvars       | —           | Affiche les instructions de création         |
| 9     | terraform init         | —           | Lance `terraform init` dans l'env par défaut |

Si tout est déjà en place, le script affiche "Ton environnement est déjà prêt."

---

## 3. Introduction

Ce projet fournit une **landing zone IaC** modulaire pour OVHcloud Public Cloud, permettant de déployer rapidement et de manière reproductible :

- Des VMs Linux avec provisionning automatique
- Des clusters Kubernetes managés (MKS), avec support multi-AZ (région Paris 3AZ)
- Des bases de données managées (DBaaS — à venir)
- Et toutes les combinaisons de ces éléments

**Principes directeurs** :

- **Mono-repo** : un seul dépôt pour tout (modules + environnements + scripts + doc)
- **Modulaire** : chaque type de ressource OVHcloud dans son propre module réutilisable
- **Flexible** : feature flags pour composer des environnements à la demande
- **Automatisé** : CLI unifiée (`infra.sh`) et script d'init (`setup.sh`)

---

## 4. Vision fonctionnelle

### 4.1 Cas d'usage cibles

```
┌──────────────────────────────────────────────────────────────┐
│  CAS D'USAGE 1 : Sandbox VM simple (POC rapide, 1 VM web)    │
│  ────────────────────────────────────────────────────────    │
│  → Utiliser l'env : sandbox-sbg5                             │
│  → Déploiement : ./infra.sh deploy -e sandbox-sbg5           │
│  → Accès : ./infra.sh ssh -e sandbox-sbg5                    │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│  CAS D'USAGE 2 : Kubernetes managé multi-AZ (démo prod-like) │
│  ────────────────────────────────────────────────────────    │
│  → Utiliser l'env : mks-sandbox-par                          │
│  → Déploiement : ./infra.sh deploy -e mks-sandbox-par        │
│  → Kubeconfig  : ./infra.sh kubeconfig -e mks-sandbox-par    │
│  → Démo        : ./infra.sh deploy-demo -e mks-sandbox-par   │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│  CAS D'USAGE 3 : Combinaison flexible (VM + MKS par ex.)     │
│  ────────────────────────────────────────────────────────    │
│  → Utiliser l'env : sandbox-par                              │
│  → Activer ce qu'on veut dans terraform.tfvars :             │
│    enable_vm    = true                                       │
│    enable_mks   = true                                       │
│    enable_dbaas = false                                      │
│  → Déploiement : ./infra.sh deploy -e sandbox-par            │
└──────────────────────────────────────────────────────────────┘
```

### 4.2 Vue fonctionnelle des composants

```
                    ┌────────────────────────────────┐
                    │    Compte OVHcloud             │
                    │  ┌──────────────────────────┐  │
                    │  │  Projet Public Cloud     │  │
                    │  │  = Tenant OpenStack      │  │
                    │  └──────────────────────────┘  │
                    └────────────────────────────────┘
                                   │
           ┌───────────────────────┼───────────────────────┐
           ▼                       ▼                       ▼
    ┌─────────────┐         ┌─────────────┐         ┌─────────────┐
    │ module      │         │ module      │         │ module      │
    │ network     │         │ compute     │         │ mks         │
    │             │         │             │         │             │
    │ • réseau    │         │ • VM        │         │ • cluster   │
    │ • subnet    │         │ • port      │         │ • nodepool  │
    │ • router    │         │ • FIP       │         │ • RBAC IP   │
    │ • sec-group │         │             │         │             │
    │ • keypair   │         │             │         │             │
    └─────────────┘         └─────────────┘         └─────────────┘
           │                       │                       │
           └───── utilisé par ─────┘                       │
                         │                                 │
                         ▼                                 ▼
                ┌──────────────────┐             ┌──────────────────┐
                │ env sandbox-sbg5 │             │ env              │
                │ (VM)             │             │ mks-sandbox-par  │
                └──────────────────┘             │ (MKS multi-AZ)   │
                                                 └──────────────────┘

                           ┌─────────────────────────┐
                           │ env sandbox-par         │
                           │ (flexible — flags)      │
                           │                         │
                           │ enable_vm    = true/false│
                           │ enable_mks   = true/false│
                           │ enable_dbaas = true/false│
                           └─────────────────────────┘
```

---

## 5. Structure du projet

```
.
├── modules/
│   ├── network/                  # Réseau privé, routeur, SG, keypair
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   ├── compute/                  # VM, port, floating IP
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   ├── mks/                      # Cluster Kubernetes managé OVHcloud
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   └── dbaas/                    # Placeholder (futur)
│       └── .gitkeep
│
├── envs/
│   ├── sandbox-sbg5/             # VM simple sur SBG5
│   ├── mks-sandbox-par/          # MKS sur Paris 3AZ
│   └── sandbox-par/              # Flexible (feature flags)
│
├── examples/
│   └── k8s-multi-az-demo/        # Manifestes démo (RBAC, ConfigMap, Deployment, Service)
│
├── docs/
│   ├── adr/                      # Architecture Decision Records (cf. § 18)
│   └── runbooks/                 # Procédures d'exploitation (à venir)
│
├── _init-project/
│   └── setup.sh                  # Installation prérequis
├── infra.sh                      # CLI unifiée (deploy, destroy, ssh, kubeconfig, full-deploy, verify, doctor...)
├── destroy.sh                    # Legacy (remplacé par infra.sh destroy / full-destroy)
├── README.md                     # Doc rapide
└── DOCUMENTATION.md              # Ce fichier
```

---

## 6. Modules Terraform

### 6.1 Module `network`

Ressources : réseau privé + subnet (toujours créés) ; routeur, security group (SSH/HTTP/HTTPS/ICMP), keypair (optionnels via feature flags).

| Variable          | Défaut                         | Description                                         |
| ----------------- | ------------------------------ | --------------------------------------------------- |
| `project_name`    | —                              | Préfixe des ressources                              |
| `region`          | —                              | Région OpenStack                                    |
| `subnet_cidr`     | `10.0.1.0/24`                  | CIDR du subnet                                      |
| `dns_nameservers` | `["213.186.33.99", "8.8.8.8"]` | DNS                                                 |
| `ext_net_id`      | `null`                         | ID du réseau Ext-Net (requis si `enable_router`)    |
| `admin_cidr`      | `null`                         | CIDR autorisé SSH (requis si `enable_secgroup`)     |
| `ssh_public_key`  | `null`                         | Clé publique SSH (requis si `enable_keypair`)       |
| `enable_router`   | `true`                         | Crée le routeur + interface (cas VM publique)       |
| `enable_secgroup` | `true`                         | Crée le security group + règles SSH/HTTP/HTTPS/ICMP |
| `enable_keypair`  | `true`                         | Crée la keypair SSH (inutile pour MKS)              |

**Outputs** : `network_id`, `subnet_id` (toujours présents) ; `secgroup_id`, `keypair_name`, `router_id` (présents seulement si flag correspondant activé, sinon `null`).

**Cas d'usage** :

- **VM publique** (sandbox-sbg5) : tous les flags à `true` (défaut).
- **MKS** (mks-sandbox-par) : tous les flags à `false` — MKS gère son propre routage et son filtrage. On ne garde que le réseau privé + subnet, requis en région 3AZ.

Cette mécanique est documentée plus en détail dans [ADR 0003](docs/adr/0003-feature-flags-module-network.md).

### 6.2 Module `compute`

Ressources : port réseau, IP flottante, instance VM, association IP↔VM.

| Variable                                                 | Défaut         | Description                |
| -------------------------------------------------------- | -------------- | -------------------------- |
| `project_name`                                           | —              | Préfixe                    |
| `region`                                                 | —              | Région OpenStack           |
| `network_id`, `subnet_id`, `secgroup_id`, `keypair_name` | —              | Fournis par module network |
| `image_name`                                             | `Ubuntu 24.04` | Image OS                   |
| `flavor_name`                                            | `d2-2`         | Flavor                     |
| `user_data`                                              | `null`         | Cloud-init                 |
| `metadata`                                               | `{}`           | Metadata instance          |

**Outputs** : `vm_name`, `vm_id`, `private_ip`, `public_ip`.

### 6.3 Module `mks`

Ressources : cluster MKS, node pool, IP restrictions (optionnel).

| Variable                                    | Défaut             | Description                                                                |
| ------------------------------------------- | ------------------ | -------------------------------------------------------------------------- |
| `service_name`                              | —                  | ID du projet Public Cloud (tenant)                                         |
| `cluster_name`                              | —                  | Nom du cluster                                                             |
| `region`                                    | —                  | Région MKS (ex: `EU-WEST-PAR`, `SBG5`)                                     |
| `kube_version`                              | `null`             | Version K8s (null = latest stable MKS)                                     |
| `update_policy`                             | `MINIMAL_DOWNTIME` | `ALWAYS_UPDATE` / `MINIMAL_DOWNTIME` / `NEVER_UPDATE`                      |
| `az_count`                                  | `2`                | 1/2/3 — nombre d'AZ logiques (validation 1/2/3)                            |
| `node_flavor`                               | `b2-7`             | Flavor workers                                                             |
| `nodes_per_pool`                            | `1`                | Nodes par AZ logique                                                       |
| `autoscale`                                 | `false`            | Active autoscaling                                                         |
| `min_nodes_per_pool` / `max_nodes_per_pool` | `1` / `3`          | Bornes autoscaling                                                         |
| `api_allowed_cidrs`                         | `[]`               | Vide = 0.0.0.0/0                                                           |
| `private_network_id`                        | `null`             | ID du réseau privé OVH (**obligatoire** en région 3AZ comme `EU-WEST-PAR`) |
| `nodes_subnet_id`                           | `null`             | ID du subnet OpenStack des nodes (**obligatoire** en région 3AZ)           |

**Outputs** : `cluster_id`, `cluster_name`, `endpoint`, `version`, `kubeconfig` (sensitive), `nodepool`, `az_count`, `total_nodes`.

> **Région 3AZ (`EU-WEST-PAR`)** : `private_network_id` ET `nodes_subnet_id` sont **obligatoires**. L'env `mks-sandbox-par` les fournit en appelant le module `network` (en mode minimal, voir § 6.1) et en passant `module.network.network_id` / `module.network.subnet_id` au module `mks`. En mono-AZ (SBG5), ces deux paramètres restent optionnels.

Voir [section 11](#11-module-mks-kubernetes-managé) pour les détails techniques et [ADR 0006](docs/adr/0006-choix-region-paris-3az-vs-sbg-mono-az.md) pour le trade-off mono-AZ vs 3AZ.

### 6.4 Module `dbaas`

**Placeholder** — non implémenté. Sera développé pour couvrir les bases managées OVHcloud (PostgreSQL, MySQL, Redis, MongoDB, Kafka…).

---

## 7. Environnements et feature flags

### 7.1 Philosophie

Chaque **environnement** est un déploiement Terraform indépendant (son propre state, ses propres variables). On distingue deux familles :

- **Envs figés** : un use case clair, pas de flag (ex: `sandbox-sbg5`, `mks-sandbox-par`)
- **Envs flexibles** : feature flags pour combiner les workloads (ex: `sandbox-par`)

### 7.2 Mécanisme des feature flags

Dans un env flexible, chaque module optionnel est conditionné via `count` :

```hcl
module "vm" {
  count  = var.enable_vm ? 1 : 0
  source = "../../modules/compute"
  ...
}

module "mks" {
  count  = var.enable_mks ? 1 : 0
  source = "../../modules/mks"
  ...
}
```

Les outputs sont adaptés :

```hcl
output "vm_public_ip" {
  value = var.enable_vm ? module.vm[0].public_ip : null
}
```

### 7.3 Schéma des envs

```
            ┌────────────────────────────────────────────────┐
            │              ENVIRONNEMENTS                    │
            └────────────────────────────────────────────────┘
                  │                │                │
    ┌─────────────▼────┐ ┌─────────▼────────┐ ┌─────▼───────────┐
    │ sandbox-sbg5     │ │ mks-sandbox-par  │ │ sandbox-par     │
    │ (figé — VM)      │ │ (figé — MKS)     │ │ (flexible)      │
    │                  │ │                  │ │                 │
    │ ✅ module network│ │ ✅ module mks    │ │ 🎚️ enable_vm    │
    │ ✅ module compute│ │                  │ │ 🎚️ enable_mks   │
    │                  │ │                  │ │ 🎚️ enable_dbaas │
    │ Région : SBG5    │ │ Région : PAR 3AZ │ │ Région : PAR/x  │
    └──────────────────┘ └──────────────────┘ └─────────────────┘
```

### 7.4 Combinaisons possibles avec sandbox-par

| `enable_vm` | `enable_mks` | `enable_dbaas` | Cas d'usage                                    |
| :---------: | :----------: | :------------: | ---------------------------------------------- |
|     ✅      |      ❌      |       ❌       | VM seule (équivalent sandbox-sbg5 mais en PAR) |
|     ❌      |      ✅      |       ❌       | MKS seul (équivalent mks-sandbox-par)          |
|     ✅      |      ✅      |       ❌       | VM + MKS (ex: VM bastion + cluster privé)      |
|     ❌      |      ✅      |       ✅       | MKS + DB managée (quand dispo)                 |
|     ✅      |      ✅      |       ✅       | Full stack (quand dbaas dispo)                 |

Le flag `enable_dbaas=true` est actuellement bloqué par une `validation` dans `variables.tf` tant que le module n'est pas implémenté.

---

## 8. Prérequis et configuration

### 8.1 Clés API OVHcloud

Générer sur <https://www.ovh.com/auth/api/createToken> avec les droits :

- `GET/POST/PUT/DELETE /cloud/*`

### 8.2 Utilisateur OpenStack (requis pour VM uniquement)

**Public Cloud → Project Management → Users & Roles** → créer un utilisateur Administrator.

### 8.3 Service Name OVH (tenant)

Visible dans l'URL de ton projet Public Cloud : `https://www.ovh.com/manager/#/public-cloud/pci/projects/<SERVICE_NAME>`.

C'est un **ID hex de 32 caractères**, pas le nom friendly du projet. L'utilisation du nom friendly renvoie un 404 sur les appels API.

Cette valeur est requise pour **MKS** (variable `ovh_service_name`).

### 8.4 openrc par région OVHcloud

Sur OVHcloud Public Cloud, **chaque région a ses propres credentials OpenStack**. Le projet attend un fichier `openrc_<REGION>.sh` par région utilisée :

- `openrc_PAR.sh` pour les déploiements en région Paris (`EU-WEST-PAR`)
- `openrc_SBG.sh` pour les déploiements en région Strasbourg (`SBG5`)
- `openrc_<XXX>.sh` pour toute autre région

Téléchargement : Manager OVH → Public Cloud → Users & Roles → cliquer sur l'utilisateur → onglet OpenRC → Download → renommer le fichier suivant la convention ci-dessus, à la racine du projet.

Ces fichiers contiennent un mot de passe en clair, ils sont **automatiquement gitignorés** (pattern `openrc*.sh`).

`infra.sh` source le bon fichier automatiquement avant chaque opération Terraform — pas besoin de `source openrc.sh` à la main. Si le fichier est absent : warning + continue (l'utilisateur peut avoir ses propres `OS_*` exportées dans son shell).

> **Cohérence env ↔ openrc** : la détection région d'`infra.sh` se base d'abord sur la variable `region` du `terraform.tfvars`, sinon sur le nom de l'env (`*par*` → PAR, `*sbg*` → SBG). Si tu utilises un env nommé `sandbox-par` mais que tes ressources OpenStack sont en GRA, le sourcing automatique enverra le mauvais openrc — privilégie un nom d'env cohérent avec la région cible (`sandbox-gra` par exemple).

Détails dans [ADR 0004](docs/adr/0004-strategie-openrc-par-region.md).

### 8.5 terraform.tfvars (exemple complet pour sandbox-par)

```hcl
# OVH API
ovh_application_key    = "..."
ovh_application_secret = "..."
ovh_consumer_key       = "..."
ovh_service_name       = "..."    # Tenant pour MKS

# Feature flags
enable_vm    = true
enable_mks   = true
enable_dbaas = false

# VM (si enable_vm=true) — credentials OpenStack en région PAR
os_tenant_id   = "..."
os_tenant_name = "..."
os_username    = "user-..."
os_password    = "..."
os_region      = "EU-WEST-PAR"
ssh_public_key = "ssh-ed25519 AAAA..."
admin_cidr     = "XX.XX.XX.XX/32"

# MKS (si enable_mks=true)
mks_region         = "EU-WEST-PAR"
mks_az_count       = 2
mks_node_flavor    = "b2-7"
mks_nodes_per_pool = 1
```

---

## 9. Script infra.sh

### 9.1 Commandes disponibles

#### Commandes Terraform

| Commande  | Options        | Rôle                                      |
| --------- | -------------- | ----------------------------------------- |
| `init`    | `-e env`       | `terraform init`                          |
| `plan`    | `-e env`       | `terraform plan`                          |
| `deploy`  | `-e env`, `-a` | `terraform apply` (auto-init si besoin)   |
| `destroy` | `-e env`, `-a` | Détache routeur OVH + `terraform destroy` |
| `output`  | `-e env`       | Affiche les outputs Terraform             |
| `status`  | `-e env`       | Affiche l'état des ressources             |
| `envs`    | —              | Liste les environnements                  |

#### Commandes VM

| Commande | Options             | Rôle                  |
| -------- | ------------------- | --------------------- |
| `ssh`    | `-e env`, `-u user` | Connexion SSH à la VM |

#### Commandes MKS

| Commande       | Options           | Rôle                                                        |
| -------------- | ----------------- | ----------------------------------------------------------- |
| `kubeconfig`   | `-e env`          | Affiche `export KUBECONFIG=...`                             |
| `wait-nodes`   | `-e env`, `-t 5m` | `kubectl wait` sur tous les nodes (timeout configurable)    |
| `deploy-demo`  | `-e env`          | Déploie la démo + `rollout status` + wait IP LB + test HTTP |
| `destroy-demo` | `-e env`          | Retire les manifestes de démo                               |

#### Orchestration end-to-end

| Commande       | Options                 | Rôle                                                                                                                           |
| -------------- | ----------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `full-deploy`  | `-e env`, `--with-demo` | `deploy` (auto-approve) → `wait-nodes` → (option `--with-demo` : `deploy-demo`) → `verify`                                     |
| `full-destroy` | `-e env`                | `destroy-demo` (si présent, avec attente libération LB Octavia) → `destroy` (auto-approve, pré-nettoie le router MKS résiduel) |

#### Diagnostic

| Commande | Options  | Rôle                                                                  |
| -------- | -------- | --------------------------------------------------------------------- |
| `verify` | `-e env` | Récap : outputs TF + nodes Kubernetes + pods + svc démo               |
| `doctor` | —        | Vérifie présence + version de terraform, kubectl, openstack, jq, curl |
| `help`   | —        | Aide complète                                                         |

### 9.2 Options globales

| Option               | Défaut         | Description                                           |
| -------------------- | -------------- | ----------------------------------------------------- |
| `-e, --env`          | `sandbox-sbg5` | Env cible                                             |
| `-u, --user`         | `ubuntu`       | User SSH                                              |
| `-a, --auto-approve` | off            | Pas de confirmation (deploy/destroy)                  |
| `-t, --timeout`      | `5m`           | Timeout pour `wait-nodes` (ex: `10m`, `300s`)         |
| `--with-demo`        | off            | Déploie aussi la démo (uniquement avec `full-deploy`) |

### 9.3 Fonctionnement interne

- **Sourcing openrc automatique** : avant chaque opération Terraform (`init`, `plan`, `deploy`, `destroy`), `infra.sh` détecte la région cible (priorité : `terraform.tfvars` > nom de l'env, ex `*par*` → PAR, `*sbg*` → SBG) et source le bon `openrc_<REGION>.sh`. Plus besoin de le faire à la main. Si le fichier est absent, warning + continue (l'utilisateur peut avoir ses propres `OS_*` exportées). Voir [ADR 0004](docs/adr/0004-strategie-openrc-par-region.md).
- **Auto-init** : `deploy` lance `terraform init` si `.terraform/` absent.
- **Détachement routeur** : `destroy` détecte la présence d'une VM (via output `vm_name`) et détache l'interface routeur OVH avant le `terraform destroy` (contournement d'une limitation OVHcloud). Cette étape utilise le client `openstack` ; les credentials sont déjà disponibles grâce au sourcing automatique fait en début de `cmd_destroy`.
- **Outputs intelligents** : les commandes `ssh`/`kubeconfig`/`wait-nodes` détectent les outputs `null` et affichent un message d'erreur explicite si le workload n'est pas activé.
- **Wait LB sur deploy-demo** : après `kubectl apply`, `infra.sh` attend le `rollout status` (timeout 2min), boucle sur l'IP publique du LoadBalancer (timeout 3min, polling 5s) et lance `curl -sfI` sur l'IP obtenue pour confirmer le succès.
- **Démo K8s** : `deploy-demo` utilise automatiquement le `kubeconfig.yaml` généré par Terraform.

---

## 10. Procédures de déploiement

### 10.1 Premier déploiement (sandbox-sbg5)

```bash
cd envs/sandbox-sbg5
cp terraform.tfvars.dist terraform.tfvars
# Éditer terraform.tfvars
cd ../..
./infra.sh deploy -e sandbox-sbg5
```

### 10.2 Déploiement MKS (mks-sandbox-par)

```bash
cd envs/mks-sandbox-par
cp terraform.tfvars.dist terraform.tfvars
# Éditer : ovh_*_key, ovh_service_name, os_tenant_id, os_tenant_name, os_username, os_password
# (les os_* sont requis car l'env appelle le module network pour le subnet privé)
cd ../..

# OPTION 1 — tout en une commande (recommandé) :
./infra.sh full-deploy -e mks-sandbox-par --with-demo
# → apply → wait-nodes Ready → deploy-demo → wait LB → curl test → verify
# → URL finale affichée à la fin

# OPTION 2 — étapes séparées (debug ou contrôle fin) :
./infra.sh deploy        -e mks-sandbox-par     # 5-10 min
./infra.sh wait-nodes    -e mks-sandbox-par     # attend Ready
./infra.sh deploy-demo   -e mks-sandbox-par     # déploie + wait LB + test HTTP
./infra.sh verify        -e mks-sandbox-par     # récap final
```

Après le deploy :

- `kubeconfig.yaml` est écrit automatiquement dans `envs/mks-sandbox-par/`
- `./infra.sh kubeconfig -e mks-sandbox-par` donne la commande `export` à utiliser
- Le bon `openrc_PAR.sh` est sourcé automatiquement (cf. § 9.3)

### 10.3 Déploiement flexible (sandbox-par)

```bash
cd envs/sandbox-par
cp terraform.tfvars.dist terraform.tfvars
# Éditer les feature flags et remplir les credentials correspondants
cd ../..

./infra.sh deploy -e sandbox-par
./infra.sh output -e sandbox-par    # voir les outputs (null si désactivé)
```

### 10.4 Vérification post-déploiement

**VM** :

```bash
./infra.sh ssh -e <env>
sudo cloud-init status   # attendu : status: done
```

**MKS** :

```bash
eval $(./infra.sh kubeconfig -e <env> | grep export)
kubectl get nodes
kubectl get pods --all-namespaces
```

---

## 11. Module MKS (Kubernetes managé)

### 11.1 Architecture MKS OVHcloud

```
                    ┌────────────────────────────────────┐
                    │       OVHcloud Data Center         │
                    │                                    │
                    │  ┌────────────────────────────┐    │
                    │  │    MKS Control Plane       │    │
                    │  │  (managé par OVHcloud)     │    │
                    │  │  - API Server              │    │
                    │  │  - etcd                    │    │
                    │  │  - Scheduler               │    │
                    │  │  - Controller Manager      │    │
                    │  │  [GRATUIT — HA en 3AZ]     │    │
                    │  └──────────────┬─────────────┘    │
                    │                 │                  │
                    │      ┌──────────┴──────────┐       │
                    │      ▼          ▼          ▼       │
                    │  ┌───────┐  ┌───────┐  ┌───────┐   │
                    │  │Worker │  │Worker │  │Worker │   │
                    │  │Node 1 │  │Node 2 │  │Node 3 │   │
                    │  │ AZ-a  │  │ AZ-b  │  │ AZ-c  │   │
                    │  │(b2-7) │  │(b2-7) │  │(b2-7) │   │
                    │  │ FACT. │  │ FACT. │  │ FACT. │   │
                    │  └───────┘  └───────┘  └───────┘   │
                    │                                    │
                    └────────────────────────────────────┘
```

### 11.2 Logique multi-AZ

En région **3AZ (Paris `EU-WEST-PAR`)** :

- Le **control plane** est automatiquement HA sur les 3 AZ
- Les **workers** sont distribués par OVH sur les AZ disponibles (anti-affinité gérée implicitement côté provider OVH, sans variable Terraform exposée)
- `az_count` dimensionne le node pool (1/2/3) — la répartition physique sur les hyperviseurs/AZ relève du scheduler OVHcloud

| `az_count` |     Total nodes      | Usage                           |
| :--------: | :------------------: | ------------------------------- |
|    `1`     |   `nodes_per_pool`   | Mono-AZ, cluster petit/dev      |
|    `2`     | `2 × nodes_per_pool` | Bi-AZ (défaut) — **recommandé** |
|    `3`     | `3 × nodes_per_pool` | Tri-AZ, HA max                  |

> **Note** : `az_count` est un contrôle **logique** Terraform qui pilote le sizing du pool. Aucune variable n'expose les noms d'AZ ni l'anti-affinité au niveau du module — ces aspects sont gérés en interne par OVH MKS (en région 3AZ, OVH garantit la distribution sur des hyperviseurs distincts).

### 11.3 Kubeconfig local

Le module expose un output `kubeconfig` (sensitive). L'environnement écrit ce contenu en local via la ressource `local_file` :

```hcl
resource "local_file" "kubeconfig" {
  content         = module.mks.kubeconfig
  filename        = "${path.module}/kubeconfig.yaml"
  file_permission = "0600"
}
```

Le fichier `kubeconfig.yaml` est **gitignoré** (il contient les certificats d'accès au cluster).

### 11.4 IP restrictions sur l'API

Par défaut (`api_allowed_cidrs = []`), l'API Kube est accessible depuis `0.0.0.0/0`. La sécurité repose sur les certificats du kubeconfig.

Pour restreindre (prod) :

```hcl
api_allowed_cidrs = ["203.0.113.42/32", "198.51.100.0/24"]
```

### 11.5 Private network (réseau privé)

Le module accepte deux variables liées au réseau privé :

- `private_network_id` : ID du réseau privé OVH
- `nodes_subnet_id` : ID du subnet OpenStack où seront placés les nodes

**Caractère obligatoire selon la région** :

| Région                     | `private_network_id` | `nodes_subnet_id` |
| -------------------------- | -------------------- | ----------------- |
| Mono-AZ (`SBG5`, `GRA`, …) | optionnel            | optionnel         |
| 3AZ (`EU-WEST-PAR`)        | **obligatoire**      | **obligatoire**   |

**Provisionnement minimal en 3AZ** : l'env `mks-sandbox-par` appelle le module `network` en mode minimal (tous les flags `enable_*` à `false`), puis passe `module.network.network_id` et `module.network.subnet_id` au module `mks` :

```hcl
module "network" {
  source = "../../modules/network"
  # ...
  enable_router   = false
  enable_secgroup = false
  enable_keypair  = false
  subnet_cidr     = var.subnet_cidr  # ex: 10.200.1.0/24
}

module "mks" {
  source             = "../../modules/mks"
  private_network_id = module.network.network_id
  nodes_subnet_id    = module.network.subnet_id
  # ...
}
```

---

## 12. Démo Kubernetes multi-AZ

Répertoire : `examples/k8s-multi-az-demo/`

### 12.1 Objectif

Démontrer visuellement la répartition multi-AZ : une page web affichée dans le navigateur indique **quelle zone** a servi la requête, avec une couleur différente par AZ.

### 12.2 Architecture

```
   Internet
      │
      ▼
┌──────────────────────────────────┐
│   Service type=LoadBalancer      │
│   (Octavia LB OVHcloud auto)     │
│   IP publique : XX.XX.XX.XX      │
└──────────────────────────────────┘
      │ round-robin
      ├──────────────┬──────────────┐
      ▼              ▼              ▼
   ┌─────┐       ┌─────┐         ┌─────┐
   │ Pod │       │ Pod │         │ Pod │
   │nginx│       │nginx│         │nginx│
   │AZ-a │       │AZ-b │         │AZ-a │
   │ 🔵  │       │ 🟢  │         │ 🔵  │
   └─────┘       └─────┘         └─────┘
     │            │                 │
     │ via RBAC ServiceAccount      │
     └───────┬────┴─────────────────┘
             ▼
    ┌──────────────────┐
    │ Kubernetes API   │
    │ kubectl get node │
    │ → label zone     │
    └──────────────────┘
```

### 12.3 Composants

| Fichier              | Rôle                                                                                                                               |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `00-rbac.yaml`       | `ServiceAccount node-reader` + `ClusterRole` (get/list nodes) + `ClusterRoleBinding`                                               |
| `01-configmap.yaml`  | Script shell qui génère l'HTML avec la zone, la région et le nom du node                                                           |
| `02-deployment.yaml` | Deployment nginx (6 replicas) + init container `bitnami/kubectl` + `topologySpreadConstraints` pour forcer la répartition inter-AZ |
| `03-service.yaml`    | Service `type=LoadBalancer` → Octavia LB OVHcloud créé automatiquement                                                             |

### 12.4 Workflow du pod

```
1. Scheduler K8s → place le pod sur un node (ex: AZ-a)
2. Init container démarre (image bitnami/kubectl)
     │
     ├─ Lit NODE_NAME via downward API (spec.nodeName)
     ├─ Utilise le token du SA "node-reader" pour appeler l'API Kube
     ├─ kubectl get node $NODE_NAME -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}'
     └─ Écrit /html/index.html avec la zone (couleur bleue/verte/rouge)
3. Container principal nginx démarre et sert /html/index.html
4. Service LoadBalancer route les requêtes → Octavia LB OVHcloud
5. Le navigateur affiche la page de la zone servant la requête (change à chaque refresh)
```

### 12.5 Déploiement

```bash
./infra.sh deploy-demo -e mks-sandbox-par
```

`infra.sh` enchaîne automatiquement :

1. `kubectl apply -f examples/k8s-multi-az-demo/` (RBAC + ConfigMap + Deployment + Service)
2. `kubectl rollout status deployment/zone-demo --timeout=2m`
3. Boucle d'attente sur l'IP publique du LoadBalancer (timeout 3min, polling 5s)
4. `curl -sfI http://<EXTERNAL-IP>` pour valider la disponibilité HTTP
5. Affiche l'URL finale prête à ouvrir dans un navigateur

Si tu préfères orchestrer toi-même : `kubectl apply` + `kubectl get svc zone-demo` (boucler jusqu'à voir l'EXTERNAL-IP) + ouvrir l'URL.

### 12.6 Suppression

**Important** : toujours supprimer la démo AVANT de détruire le cluster, sinon le LB Octavia reste orphelin (facturation continue).

```bash
./infra.sh destroy-demo -e mks-sandbox-par
./infra.sh destroy -e mks-sandbox-par
```

---

## 13. Destruction de l'infrastructure

### 13.1 Spécificité OVHcloud : interfaces routeur résiduelles

OVHcloud crée automatiquement des **interfaces routeur supplémentaires** (ports SNAT distribués) non gérées par Terraform. Elles bloquent la suppression du subnet et du routeur avec `RouterInUse (409)`.

### 13.2 Via infra.sh (recommandé)

```bash
./infra.sh destroy -e <env>           # avec confirmation
./infra.sh destroy -e <env> -a        # sans confirmation
```

Le script détecte la présence d'une VM (via l'output `vm_name`) et détache l'interface routeur avant le destroy.

### 13.3 Ordre de destruction (MKS)

Pour un cluster MKS avec démo déployée, **ne pas inverser** l'ordre — sinon le LB Octavia créé par le `Service type=LoadBalancer` reste orphelin côté OVHcloud (et continue à être facturé).

#### Option 1 — En une commande (recommandé)

```bash
./infra.sh full-destroy -e <env>
# Séquence :
#  1. destroy-demo (si présent, en ignorant les erreurs)
#  2. Si LB était présent : kubectl wait svc disparu + sleep 60s (marge Octavia)
#  3. Pré-nettoyage auto du router Neutron k8s-cluster-<id> résiduel
#  4. tf destroy auto-approve
```

#### Option 2 — Étapes séparées

```bash
1. ./infra.sh destroy-demo -e <env>   # supprime les manifestes K8s (+ LB Octavia)
2. ./infra.sh destroy      -e <env>   # détruit le cluster MKS
```

---

## 14. Provisionning cloud-init

### 14.1 Contexte

Le fichier `cloud-init.yaml` (dans les envs avec VM) est passé comme `user_data` au module compute. OVHcloud l'exécute au premier boot.

### 14.2 Séquence VM sandbox

| Ordre | Action                   | Détail                                |
| ----- | ------------------------ | ------------------------------------- |
| 1     | `write_files`            | Écrit `index.html` et la config Nginx |
| 2     | `apt-get update` (retry) | Boucle jusqu'à dispo réseau           |
| 3     | `apt-get install`        | Installe `nginx` et `openssl`         |
| 4     | `openssl req`            | Génère certificat auto-signé RSA 2048 |
| 5     | `ln -s`                  | Active la config dans `sites-enabled` |
| 6     | `systemctl restart`      | Lance Nginx                           |

> **Point critique** : sur Ubuntu 24.04, le symlink `sites-available`→`sites-enabled` est obligatoire, sinon Nginx n'écoute pas.

---

## 15. Dépannage

### 15.1 Erreurs Terraform

| Erreur                                            | Cause                                                 | Solution                                                            |
| ------------------------------------------------- | ----------------------------------------------------- | ------------------------------------------------------------------- |
| `No suitable endpoint for network service in SBG` | Mauvaise région                                       | Utiliser `SBG5`                                                     |
| `ExternalGatewayForFloatingIPNotFound`            | Interface routeur détachée                            | `./infra.sh destroy` puis `./infra.sh deploy`                       |
| `RouterInUse (409)` au destroy                    | Ports OVH résiduels                                   | Géré auto : `./infra.sh destroy` pré-nettoie le router MKS résiduel |
| `Unsupported argument: availability_zones`        | Provider OVH < 0.51                                   | `terraform init -upgrade`                                           |
| `failed to generate fingerprint`                  | Mauvaise clé SSH                                      | Passer le contenu direct (pas le chemin)                            |
| `Inconsistent dependency lock file`               | Contraintes versions module ↔ env incompatibles       | Aligner `versions.tf`, `terraform init -upgrade` (ADR 0005)         |
| `plan is not compatible with this region`         | Plan Discovery sur région 3AZ (PAR)                   | Upgrade plan en Essentials dans le Manager OVH (ADR 0006)           |
| `404` sur appels API OVH                          | `ovh_service_name` = nom friendly au lieu de l'ID hex | Utiliser l'ID hex 32 chars du tenant (URL Manager)                  |
| MKS create : `nodes_subnet_id required`           | Région 3AZ sans subnet fourni                         | Ajouter `private_network_id` + `nodes_subnet_id` (cf. § 11.5)       |
| `openrc absent` (warning)                         | Pas de `openrc_<REGION>.sh` à la racine               | Télécharger depuis Manager OVH et renommer (cf. § 8.5)              |

### 15.2 Erreurs Nginx / cloud-init

| Symptôme                               | Solution                                                                         |
| -------------------------------------- | -------------------------------------------------------------------------------- |
| `curl: (7) Failed to connect port 443` | Vérifier le symlink `sites-enabled`                                              |
| `Unit nginx.service not found`         | Relancer manuellement `apt install -y nginx`                                     |
| `sites-enabled` vide                   | `sudo ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default` |

### 15.3 Erreurs MKS

| Symptôme                                      | Cause                                     | Solution                                                               |
| --------------------------------------------- | ----------------------------------------- | ---------------------------------------------------------------------- |
| `./infra.sh kubeconfig` → "Aucun cluster MKS" | Cluster non déployé ou `enable_mks=false` | Vérifier avec `./infra.sh output -e <env>`                             |
| `kubectl` → `Unable to connect to the server` | Mauvais kubeconfig                        | Recharger avec `eval $(./infra.sh kubeconfig -e <env> \| grep export)` |
| Pods en `Pending` longtemps                   | Node pool pas encore prêt                 | `kubectl get nodes` — attendre que tous soient `Ready`                 |
| Service LoadBalancer reste `<pending>`        | LB en cours de provisionnement            | Patienter 1-2 min                                                      |
| URL LB timeout juste après deploy-demo        | FloatingIP Octavia pas encore routable    | Attendre 3-5 min après `EnsuredLoadBalancer` — propagation réseau OVH  |
| Timeout 10 min sur subnet au destroy          | Router MKS résiduel `k8s-cluster-<id>`    | Géré auto par `cmd_destroy` depuis le fix de 2026-04-16                |
| Après destroy : IP publique toujours facturée | LB Octavia orphelin                       | `openstack loadbalancer list` et supprimer manuellement                |

### 15.4 Commandes de diagnostic

```bash
# VM
./infra.sh ssh -e <env>
sudo cloud-init status
sudo cat /var/log/cloud-init-output.log

# MKS
kubectl get nodes -o wide
kubectl get pods --all-namespaces
kubectl describe node <node-name>
kubectl logs -n kube-system <pod>

# OVHcloud
openstack server list
openstack loadbalancer list
```

---

## 16. Estimation des coûts

### 16.1 Sandbox VM (sandbox-sbg5)

| Ressource                       | Coût /mois HT |
| ------------------------------- | ------------- |
| VM d2-2 (1 vCPU / 2 GB / 25 GB) | ~2,20 €       |
| IP flottante                    | ~2,90 €       |
| **Total**                       | **~5,10 €**   |

### 16.2 MKS multi-AZ (mks-sandbox-par, az_count=2)

| Ressource                                | Coût /mois HT |
| ---------------------------------------- | ------------- |
| Control plane MKS                        | **Gratuit**   |
| 2 × workers b2-7 (2 vCPU / 7 GB / 50 GB) | ~36 €         |
| Octavia LB (démo active)                 | ~12 €         |
| **Total**                                | **~48 €**     |

Pour `az_count=3` : +18 €/mois (1 worker de plus) = ~66 €/mois.

### 16.3 Conseils

- **Toujours destroy** après usage sandbox (la facturation est à l'heure)
- **Supprimer la démo** avant le cluster (sinon LB orphelin)
- Les tarifs OVHcloud sont susceptibles d'évoluer — consulter la grille en vigueur

---

## 17. Évolutions possibles

| Évolution                           | Description                                                         | Complexité |
| ----------------------------------- | ------------------------------------------------------------------- | ---------- |
| **Backend S3 OVHcloud**             | Stocker le tfstate dans un bucket S3 OVHcloud                       | Faible     |
| **Module DBaaS**                    | Implémenter `modules/dbaas/` (PostgreSQL/MySQL/Redis/MongoDB/Kafka) | Moyenne    |
| **Private MKS**                     | Intégration réseau privé via Gateway OVHcloud                       | Moyenne    |
| **Ingress controller**              | nginx-ingress ou Traefik en frontal du cluster                      | Moyenne    |
| **cert-manager + Let's Encrypt**    | Certificats TLS valides automatisés                                 | Faible     |
| **Monitoring**                      | Prometheus + Grafana via Helm                                       | Moyenne    |
| **GitOps (ArgoCD/Flux)**            | Déploiement continu des manifestes K8s                              | Moyenne    |
| **Ansible**                         | Remplacer cloud-init par Ansible pour les VMs                       | Moyenne    |
| **Multi-VM + LB Octavia Terraform** | Déployer un cluster HA de VMs via LB                                | Élevée     |

---

## 18. Décisions d'architecture (ADR)

Les décisions techniques structurantes du projet sont documentées dans `docs/adr/` au format Michael Nygard étendu (Status / Contexte / Options / Décision / Conséquences / Alternatives non explorées / Références croisées).

| ADR                                                                      | Décision                                                  |
| ------------------------------------------------------------------------ | --------------------------------------------------------- |
| [0001](docs/adr/0001-managed-kubernetes-vs-self-managed.md)              | Choix de Managed Kubernetes (MKS) plutôt que self-managed |
| [0002](docs/adr/0002-structure-environnements-dedies-vs-flexible.md)     | Structure des environnements : dédiés + flexible          |
| [0003](docs/adr/0003-feature-flags-module-network.md)                    | Feature flags dans le module network                      |
| [0004](docs/adr/0004-strategie-openrc-par-region.md)                     | Stratégie openrc séparée par région OVHcloud              |
| [0005](docs/adr/0005-versions-providers-modules-souples-envs-stricts.md) | Versions providers : modules souples, envs stricts        |
| [0006](docs/adr/0006-choix-region-paris-3az-vs-sbg-mono-az.md)           | Choix de région : Paris 3AZ vs SBG mono-AZ                |

Pour ajouter un nouvel ADR : créer `docs/adr/NNNN-titre-en-kebab-case.md` avec un statut `proposed` puis `accepted` après validation. Une fois `accepted`, l'ADR est immutable — pour le changer, écrire un nouvel ADR qui le supersede.

---

_Johan Protin — Avril 2026_
