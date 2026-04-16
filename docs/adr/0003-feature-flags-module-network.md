# 0003 — Feature flags dans le module network

- **Status** : accepted
- **Date** : 2026-04-16
- **Auteur(s)** : protin
- **Tags** : terraform, modules, réutilisabilité

## Contexte

Le module `modules/network/` provisionne historiquement un ensemble cohérent de ressources OpenStack pour héberger une VM publique : réseau privé, subnet, routeur (vers external network), security group avec règles SSH/HTTP/HTTPS/ICMP, et keypair SSH. Cette composition est parfaite pour `envs/sandbox-sbg5` (VM publique) mais devient inadaptée quand on l'utilise depuis `envs/mks-sandbox-par` :

- MKS gère lui-même l'attribution d'IP et le filtrage réseau au niveau du cluster
- pas besoin d'un routeur (les nodes MKS n'ont pas besoin d'IPs flottantes individuelles, OVH le gère)
- pas besoin de security group (les contraintes sont dans le control plane MKS)
- pas besoin de keypair (les nodes MKS ne sont pas accessibles SSH)

On a néanmoins besoin du **réseau privé + subnet** car la région 3AZ EU-WEST-PAR exige `private_network_id` et `nodes_subnet_id` à la création du cluster.

## Options envisagées

### Option 1 : Dupliquer le module en `network/` et `network-mks/`

- **Description** : un module séparé pour MKS, ne provisionnant que network + subnet.
- **Pour** : chaque module reste minimal et lisible.
- **Contre** : duplication de la logique réseau privé + subnet, dérive possible si l'un évolue, multiplication des modules à comprendre.
- **Coût** : N modules pour N usages.

### Option 2 : Forcer la composition côté env (network minimal pour MKS, network+VM pour VM)

- **Description** : sortir routeur/secgroup/keypair du module network. Les envs qui les veulent les déclarent eux-mêmes.
- **Pour** : modules ultra-modulaires.
- **Contre** : envs deviennent verbeux (l'env VM doit déclarer 5+ ressources à la main), perte de la cohérence "pack VM standard" du module.
- **Coût** : friction onboarding pour de nouveaux envs.

### Option 3 : Feature flags dans le module network

- **Description** : ajouter des variables booléennes `enable_router`, `enable_secgroup`, `enable_keypair` (default `true` pour préserver le comportement existant). Les envs MKS passent les 3 à `false`.
- **Pour** : module unique, un seul endroit à maintenir, comportement par défaut inchangé (compat back).
- **Contre** : le code module devient un peu plus dense (`count = var.enable_X ? 1 : 0`), les outputs doivent gérer le cas "ressource absente" (`try()` ou index `[0]`).
- **Coût** : marginal, contenu dans un seul fichier.

## Décision

Nous retenons **l'Option 3 — feature flags dans le module network**.

C'est le meilleur compromis entre DRY (un seul module) et flexibilité (chaque env active ce dont il a besoin). Les valeurs par défaut (`true` partout) garantissent la rétrocompatibilité avec les envs existants. L'env MKS passe simplement `enable_router = false`, `enable_secgroup = false`, `enable_keypair = false`.

## Conséquences

### Positives

- Module unique à maintenir, évolutions de la logique réseau propagées partout
- Comportement par défaut inchangé : l'env VM existant ne nécessite aucune modification
- Permet d'ajouter de futurs cas d'usage (ex : env DBaaS sans VM publique) en jouant sur les flags
- Coût de l'évolution localisé (3 vars + `count` sur les ressources concernées)

### Négatives / Coûts

- Lecture du module un peu plus dense (`count = var.enable_X ? 1 : 0` sur 5 ressources)
- Outputs des ressources optionnelles passent par des index `[0]` ou `try()` — friction mineure pour les envs consommateurs
- Tentation à l'avenir d'ajouter encore plus de flags : il faudra savoir s'arrêter avant que le module devienne illisible

### Neutres / À surveiller

- Si on dépasse 4-5 flags, reconsidérer un split du module
- Tests : il faut couvrir au minimum les 2 combinaisons (tout activé / tout désactivé) — pas de framework de test Terraform actuellement, vérification manuelle via `terraform plan` dans chaque env

## Alternatives non explorées (et pourquoi)

- **Submodules dans `modules/network/`** (`network/router/`, `network/secgroup/`...) : surdimensionné pour 3 ressources optionnelles, casserait le pattern "un module = un dossier".
- **Module dynamique avec `for_each` sur une liste de ressources à créer** : trop d'abstraction pour le gain.

## Références

- ADR 0002 — Structure des environnements (les feature flags du module sont l'écho de ceux de l'env flexible)
- `modules/network/main.tf` — implémentation des flags
