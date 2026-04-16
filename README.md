# OVHcloud Public Cloud — Landing Zone IaC

Infrastructure as Code modulaire pour déployer des environnements sur OVHcloud Public Cloud avec Terraform : VM, Kubernetes managé (MKS), bases de données managées (DBaaS — à venir).

## Structure du projet

```
.
├── modules/                      # Modules Terraform réutilisables
│   ├── network/                  # Réseau privé, subnet (+ optionnels : routeur, security group, keypair)
│   ├── compute/                  # VM générique (instance, port, floating IP)
│   ├── mks/                      # Cluster Kubernetes managé OVHcloud
│   └── dbaas/                    # Bases de données managées (futur)
│
├── envs/                         # Environnements de déploiement
│   ├── sandbox-sbg5/             # VM simple sur SBG5 (démo initiale)
│   ├── mks-sandbox-par/          # Cluster MKS seul sur Paris 3AZ (multi-AZ)
│   └── sandbox-par/              # Env flexible avec feature flags (VM + MKS + DBaaS)
│
├── examples/                     # Manifestes Kubernetes prêts à l'emploi
│   └── k8s-multi-az-demo/        # Démo nginx affichant la zone servant la requête
│
├── docs/
│   ├── adr/                      # Architecture Decision Records (décisions techniques)
│   └── runbooks/                 # Procédures d'exploitation (à venir)
│
├── _init-project/
│   └── setup.sh                  # Installation automatique des prérequis
├── infra.sh                      # CLI de gestion (deploy, destroy, ssh, kubeconfig, full-deploy...)
├── README.md
└── DOCUMENTATION.md              # Documentation technique complète
```

## Architecture globale

```
                          ┌──────────────────────────────┐
                          │  Compte OVHcloud             │
                          │  + Projet Public Cloud       │
                          └──────────────────────────────┘
                                        │
           ┌────────────────────────────┼────────────────────────────┐
           ▼                            ▼                            ▼
    ┌────────────┐              ┌────────────┐              ┌────────────┐
    │  VM        │              │  MKS       │              │  DBaaS     │
    │  Ubuntu    │              │  Kubernetes│              │  (futur)   │
    │  + Nginx   │              │  3-AZ HA   │              │            │
    └────────────┘              └────────────┘              └────────────┘
    sandbox-sbg5               mks-sandbox-par               (non impl.)
                                        +
                              sandbox-par (flexible)
```

## Environnements disponibles

| Env               | Description                                            | Composants                                  |
| ----------------- | ------------------------------------------------------ | ------------------------------------------- |
| `sandbox-sbg5`    | Démo VM simple sur SBG5                                | VM uniquement                               |
| `mks-sandbox-par` | Cluster Kubernetes sur Paris 3AZ (multi-AZ par défaut) | MKS uniquement                              |
| `sandbox-par`     | Env flexible combinable                                | VM + MKS + DBaaS au choix via feature flags |

## Prérequis

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5.0
- [python-openstackclient](https://docs.openstack.org/python-openstackclient/) >= 6.0
- [kubectl](https://kubernetes.io/docs/tasks/tools/) >= 1.28 (pour MKS)
- `jq` (parsing des outputs JSON kubectl)
- `curl` (test HTTP des LoadBalancers déployés par la démo)
- Git >= 2.34
- Un compte OVHcloud avec un projet Public Cloud
- Clés API OVHcloud ([générer ici](https://www.ovh.com/auth/api/createToken))
- Pour les déploiements VM : un utilisateur OpenStack créé dans le projet Public Cloud
- Pour le MKS en région Paris 3AZ : un plan **Essentials** ou supérieur (Discovery refusé sur EU-WEST-PAR)
- Une clé SSH générée localement
- Un fichier `openrc_<REGION>.sh` par région utilisée (`openrc_PAR.sh`, `openrc_SBG.sh`...) — téléchargeable depuis le Manager OVH (Public Cloud → Users & Roles → OpenRC), ils sont automatiquement gitignorés

### Installation automatique

Le script `_init-project/setup.sh` vérifie et installe tous les outils nécessaires (terraform, openstack, git, kubectl, jq, curl) puis initialise Terraform si besoin :

```bash
./_init-project/setup.sh
```

Ou via `./infra.sh doctor` pour un check rapide sans installation.

## Utilisation rapide avec infra.sh

> Le bon `openrc_*.sh` est sourcé automatiquement par `infra.sh` selon la région détectée pour l'env cible (priorité : `terraform.tfvars` > nom de l'env). Plus besoin de `source openrc.sh` à la main.

### Commandes Terraform

```bash
./infra.sh help                             # Aide complète
./infra.sh envs                             # Liste les environnements
./infra.sh init    -e <env>                 # terraform init
./infra.sh plan    -e <env>                 # terraform plan
./infra.sh deploy  -e <env> [-a]            # terraform apply (-a = auto-approve)
./infra.sh destroy -e <env> [-a]            # terraform destroy
./infra.sh output  -e <env>                 # outputs Terraform
./infra.sh status  -e <env>                 # état des ressources
```

### Commandes VM

```bash
./infra.sh ssh -e <env>                     # SSH (ubuntu par défaut)
./infra.sh ssh -e <env> -u root             # SSH avec un autre user
```

### Commandes MKS

```bash
./infra.sh kubeconfig    -e <env>           # Affiche export KUBECONFIG=...
./infra.sh wait-nodes    -e <env> [-t 5m]   # Attend que tous les nodes soient Ready
./infra.sh deploy-demo   -e <env>           # Déploie la démo + wait LB + test HTTP
./infra.sh destroy-demo  -e <env>           # Retire la démo
```

### Orchestration end-to-end

```bash
./infra.sh full-deploy   -e <env> [--with-demo]   # apply → wait-nodes → (option démo) → verify
./infra.sh full-destroy  -e <env>                 # destroy-demo (si présent) → terraform destroy
```

### Diagnostic

```bash
./infra.sh verify  -e <env>                 # Récap : outputs TF + nodes + pods + svc démo
./infra.sh doctor                           # Check de tous les prérequis (versions)
```

## Exemples de workflows

### Déployer une VM simple

```bash
cd envs/sandbox-sbg5
cp terraform.tfvars.dist terraform.tfvars
# Éditer terraform.tfvars avec tes valeurs
cd ../..
./infra.sh deploy -e sandbox-sbg5
./infra.sh ssh    -e sandbox-sbg5
```

### Déployer un cluster MKS multi-AZ + démo en une commande

```bash
cd envs/mks-sandbox-par
cp terraform.tfvars.dist terraform.tfvars
# Éditer terraform.tfvars (au minimum : ovh_*_key, ovh_service_name, os_*)
cd ../..

# Tout en une commande : apply → wait-nodes Ready → deploy-demo → wait LB → curl test → verify
./infra.sh full-deploy -e mks-sandbox-par --with-demo

# L'URL finale est affichée à la fin (http://<EXTERNAL-IP>)
```

Si tu préfères les étapes séparées :

```bash
./infra.sh deploy        -e mks-sandbox-par     # 5-10 min
./infra.sh wait-nodes    -e mks-sandbox-par     # attend Ready
./infra.sh deploy-demo   -e mks-sandbox-par     # déploie + wait LB + test HTTP
./infra.sh verify        -e mks-sandbox-par     # récap final
```

### Tout retirer en une commande

```bash
./infra.sh full-destroy -e mks-sandbox-par      # retire la démo + détruit le cluster
```

### Déployer une combinaison VM + MKS

```bash
cd envs/sandbox-par
cp terraform.tfvars.dist terraform.tfvars

# Éditer terraform.tfvars :
#   enable_vm    = true
#   enable_mks   = true
#   enable_dbaas = false
# + remplir les credentials OVH et OpenStack

cd ../..
./infra.sh deploy -e sandbox-par
```

## Coûts estimés (à titre indicatif)

| Ressource                                    | Coût mensuel HT |
| -------------------------------------------- | --------------- |
| VM d2-2 + IP flottante (sandbox-sbg5)        | ~5 €/mois       |
| MKS control plane                            | **Gratuit**     |
| 2 workers b2-7 (mks-sandbox-par, az_count=2) | ~36 €/mois      |
| Octavia LB (déployé par la démo)             | ~12 €/mois      |
| Plan Essentials (requis pour Paris 3AZ)      | abonnement OVH  |

> Les tarifs peuvent varier, consulter la grille tarifaire OVHcloud.

## Décisions d'architecture (ADR)

Les décisions techniques structurantes sont documentées dans `docs/adr/` (format Michael Nygard étendu) :

| ADR                                                                      | Décision                                                            |
| ------------------------------------------------------------------------ | ------------------------------------------------------------------- |
| [0001](docs/adr/0001-managed-kubernetes-vs-self-managed.md)              | Choix de Managed Kubernetes (MKS) plutôt que self-managed           |
| [0002](docs/adr/0002-structure-environnements-dedies-vs-flexible.md)     | Structure des environnements : dédiés + flexible avec feature flags |
| [0003](docs/adr/0003-feature-flags-module-network.md)                    | Feature flags dans le module network                                |
| [0004](docs/adr/0004-strategie-openrc-par-region.md)                     | Stratégie openrc séparée par région OVHcloud                        |
| [0005](docs/adr/0005-versions-providers-modules-souples-envs-stricts.md) | Versions providers : modules souples, envs stricts                  |
| [0006](docs/adr/0006-choix-region-paris-3az-vs-sbg-mono-az.md)           | Choix de région : Paris 3AZ (HA payant) vs SBG mono-AZ (cheap)      |

## Dépannage rapide

| Erreur                                                   | Solution                                                                       |
| -------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `No suitable endpoint for network service in SBG region` | Utiliser `SBG5` (pas `SBG`)                                                    |
| `RouterInUse` lors du destroy                            | `./infra.sh destroy` détache automatiquement l'interface                       |
| `Aucune VM déployée`                                     | Vérifier `enable_vm=true` (env flexibles)                                      |
| `Aucun cluster MKS déployé`                              | Vérifier `enable_mks=true` (env flexibles)                                     |
| Nginx ne répond pas                                      | `sudo cloud-init status` via `./infra.sh ssh`                                  |
| Pod MKS en ImagePullBackOff                              | Vérifier l'accès Internet du cluster                                           |
| `Inconsistent dependency lock file`                      | Aligner les contraintes module/env (ADR 0005), `terraform init -upgrade`       |
| `plan is not compatible with this region`                | Région 3AZ exige plan Essentials, upgrader le plan dans le Manager OVH         |
| `404` sur `ovh_service_name`                             | Utiliser l'**ID hex 32 chars** du tenant, pas le nom friendly du projet        |
| `openrc absent` au déploiement                           | Télécharger `openrc.sh` depuis Manager OVH et le renommer `openrc_<REGION>.sh` |

Pour plus de détails, voir [DOCUMENTATION.md](./DOCUMENTATION.md).
