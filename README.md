# OVHcloud Public Cloud — Landing Zone IaC

Infrastructure as Code modulaire pour déployer des environnements sur OVHcloud Public Cloud avec Terraform : VM, Kubernetes managé (MKS), bases de données managées (DBaaS — à venir).

## Structure du projet

```
.
├── modules/                      # Modules Terraform réutilisables
│   ├── network/                  # Réseau privé, routeur, security groups, keypair
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
├── _init-project/
│   └── setup.sh                  # Installation automatique des prérequis
├── infra.sh                      # CLI de gestion (deploy, destroy, ssh, kubeconfig...)
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
- Git >= 2.34
- Un compte OVHcloud avec un projet Public Cloud
- Clés API OVHcloud ([générer ici](https://www.ovh.com/auth/api/createToken))
- Un utilisateur OpenStack créé dans le projet Public Cloud (pour les déploiements VM)
- Une clé SSH générée localement

### Installation automatique

Le script `_init-project/setup.sh` vérifie et installe tous les outils nécessaires, puis initialise Terraform si besoin :

```bash
./_init-project/setup.sh
```

Si tout est déjà en place, le script affiche "Ton environnement est déjà prêt." et ne modifie rien.

## Utilisation rapide avec infra.sh

### Commandes générales

```bash
./infra.sh help                             # Aide
./infra.sh envs                             # Liste les environnements
./infra.sh init -e <env>                    # Initialise Terraform
./infra.sh plan -e <env>                    # Prévisualise
./infra.sh deploy -e <env>                  # Déploie
./infra.sh destroy -e <env>                 # Détruit
./infra.sh output -e <env>                  # Outputs Terraform
./infra.sh status -e <env>                  # État des ressources
```

### Commandes VM (sandbox-sbg5, sandbox-par avec enable_vm=true)

```bash
./infra.sh ssh -e <env>                     # SSH (ubuntu par défaut)
./infra.sh ssh -e <env> -u root             # SSH avec un autre user
```

### Commandes MKS (mks-sandbox-par, sandbox-par avec enable_mks=true)

```bash
./infra.sh kubeconfig -e <env>              # Affiche export KUBECONFIG=...
./infra.sh deploy-demo -e <env>             # Applique la démo multi-AZ
./infra.sh destroy-demo -e <env>            # Supprime la démo
```

## Exemples de workflows

### Déployer une VM simple

```bash
cd envs/sandbox-sbg5
cp terraform.tfvars.dist terraform.tfvars
# Éditer terraform.tfvars avec tes valeurs
cd ../..
./infra.sh deploy -e sandbox-sbg5
./infra.sh ssh -e sandbox-sbg5
```

### Déployer un cluster MKS multi-AZ

```bash
cd envs/mks-sandbox-par
cp terraform.tfvars.dist terraform.tfvars
# Éditer terraform.tfvars (au minimum : ovh_service_name, ovh_*_key)
cd ../..

# Déployer le cluster (5-10 min)
./infra.sh deploy -e mks-sandbox-par

# Configurer kubectl
eval $(./infra.sh kubeconfig -e mks-sandbox-par | grep export)
kubectl get nodes

# Déployer la démo multi-AZ
./infra.sh deploy-demo -e mks-sandbox-par

# Récupérer l'IP publique du LoadBalancer (patienter 1-2 min)
kubectl get svc zone-demo
# Puis ouvrir http://<EXTERNAL-IP> dans un navigateur
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

> Les tarifs peuvent varier, consulter la grille tarifaire OVHcloud.

## Dépannage rapide

| Erreur                                                   | Solution                                                 |
| -------------------------------------------------------- | -------------------------------------------------------- |
| `No suitable endpoint for network service in SBG region` | Utiliser `SBG5` (pas `SBG`)                              |
| `RouterInUse` lors du destroy                            | `./infra.sh destroy` détache automatiquement l'interface |
| `Aucune VM déployée`                                     | Vérifier `enable_vm=true` (env flexibles)                |
| `Aucun cluster MKS déployé`                              | Vérifier `enable_mks=true` (env flexibles)               |
| Nginx ne répond pas                                      | `sudo cloud-init status` via `./infra.sh ssh`            |
| Pod MKS en ImagePullBackOff                              | Vérifier l'accès Internet du cluster                     |

Pour plus de détails, voir [DOCUMENTATION.md](./DOCUMENTATION.md).
