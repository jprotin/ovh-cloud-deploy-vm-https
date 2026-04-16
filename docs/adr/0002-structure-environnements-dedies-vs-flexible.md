# 0002 — Structure des environnements : dédiés + flexible avec feature flags

- **Status** : accepted
- **Date** : 2026-04-16
- **Auteur(s)** : protin
- **Tags** : architecture, terraform, organisation

## Contexte

Le projet doit pouvoir provisionner plusieurs types de ressources OVHcloud (VM, MKS, futur DBaaS) dans plusieurs régions (SBG5, EU-WEST-PAR), avec des cas d'usage variés :

- démo simple d'une VM Nginx (rapide, pas cher) ;
- cluster Kubernetes seul, multi-AZ (HA, démo K8s) ;
- combinaison VM + MKS + DBaaS pour tester une stack complète.

Chaque cas d'usage a ses propres providers, variables, et contraintes (ex : MKS en région 3AZ exige un réseau privé pré-provisionné). On ne veut pas dupliquer le code pour chaque combinaison, mais on veut aussi pouvoir lancer un cas isolé sans embarquer de complexité.

## Options envisagées

### Option 1 : Un environnement unique, ultra-flexible

- **Description** : un seul `envs/sandbox/` avec tous les feature flags (`enable_vm`, `enable_mks`, `enable_dbaas`, `region`, `multi_az`...).
- **Pour** : code unique, DRY maximal.
- **Contre** : `terraform.tfvars` complexe à remplir, risque d'oublier un flag, lock file unique pour tous les providers (alourdit `terraform init`), state Terraform unique pour des ressources hétérogènes.
- **Coût** : maintenance complexe, friction onboarding élevée.

### Option 2 : Un environnement par cas d'usage strict (full duplication)

- **Description** : `envs/vm-sbg5/`, `envs/mks-par/`, `envs/vm-mks-par/`, `envs/vm-mks-dbaas-par/`...
- **Pour** : chaque env est minimal et compréhensible isolément, lock files séparés.
- **Contre** : explosion combinatoire, duplication massive de code, chaque évolution doit être propagée partout.
- **Coût** : maintenance N×M.

### Option 3 : Hybride — envs dédiés simples + un env flexible pour les combinaisons

- **Description** :
  - `envs/sandbox-sbg5/` : VM seule sur SBG5 (démo cheap, mono-ressource).
  - `envs/mks-sandbox-par/` : MKS seul sur Paris 3AZ (démo K8s HA).
  - `envs/sandbox-par/` : env flexible avec `enable_vm` / `enable_mks` / `enable_dbaas` pour tester les combinaisons.
- **Pour** : les envs dédiés restent triviaux à comprendre et à lancer, l'env flexible couvre les cas combinés sans dupliquer la logique des modules.
- **Contre** : 2 patterns à comprendre (env dédié vs env flexible), un peu plus de code total qu'avec l'Option 1.

## Décision

Nous retenons **l'Option 3 — hybride dédiés + flexible**.

Les envs dédiés (`sandbox-sbg5`, `mks-sandbox-par`) servent les usages mono-ressource les plus fréquents (démos rapides, isolation, troubleshooting). L'env flexible (`sandbox-par`) couvre les combinaisons sans relancer la duplication. La logique métier reste centralisée dans `modules/`, les envs ne font que composer.

## Conséquences

### Positives

- Démos rapides via les envs dédiés (`./infra.sh deploy -e sandbox-sbg5`)
- Combinaisons couvertes sans explosion combinatoire
- Lock files Terraform séparés (changement de version d'un provider n'affecte que les envs concernés)
- States Terraform séparés par cas d'usage (blast radius isolé)

### Négatives / Coûts

- Deux patterns d'env coexistent : il faut documenter clairement quand utiliser lequel
- L'env flexible (`sandbox-par`) a un `terraform.tfvars` plus chargé (variables OVH + OS + flags + paramètres par module)
- Quand un module évolue, les 3 envs peuvent être impactés — vérifier `terraform plan` partout

### Neutres / À surveiller

- Si on ajoute beaucoup plus d'envs dédiés (par client, par région), reconsidérer un workspace Terraform ou un générateur (Terragrunt)
- Si l'env flexible devient le seul utilisé, on pourra archiver les dédiés

## Alternatives non explorées (et pourquoi)

- **Terragrunt** : surdimensionné pour un projet sandbox solo, ajoute une couche d'abstraction non justifiée à ce stade.
- **Terraform workspaces** : déconseillés par HashiCorp pour les environnements multi-régions / multi-tenants ; ne séparent pas vraiment les fichiers, juste les states.

## Références

- ADR 0003 — Feature flags dans le module network (mécanique similaire au niveau module)
- ADR 0006 — Choix de région
