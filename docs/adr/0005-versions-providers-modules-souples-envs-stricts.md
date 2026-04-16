# 0005 — Contraintes de versions des providers Terraform : modules souples, envs stricts

- **Status** : accepted
- **Date** : 2026-04-16
- **Auteur(s)** : protin
- **Tags** : terraform, providers, dépendances

## Contexte

Le projet utilise plusieurs providers Terraform (`ovh/ovh`, `terraform-provider-openstack/openstack`, `hashicorp/local`, `hashicorp/random`...) déclarés à deux niveaux :

- **Modules** (`modules/network/`, `modules/mks/`, `modules/compute/`) : déclarent les providers requis dans `versions.tf` pour pouvoir être utilisés isolément.
- **Environnements** (`envs/sandbox-sbg5/`, `envs/mks-sandbox-par/`, `envs/sandbox-par/`) : déclarent aussi les providers, configurent leur authentification, et génèrent un `.terraform.lock.hcl` lors du `terraform init`.

Lors d'un `terraform init` sur un env, Terraform calcule l'**intersection** des contraintes de version déclarées par l'env et celles déclarées par chaque module appelé. Si l'intersection est vide, on obtient l'erreur :

```bash
Inconsistent dependency lock file
The given lock file (.terraform.lock.hcl) does not match the providers...
```

Cette erreur est apparue lors du déploiement initial Paris : le module `mks/` exigeait `ovh ~> 0.49` alors que l'env demandait `ovh ~> 0.46`. Sans intersection valide, blocage.

## Options envisagées

### Option 1 : Contraintes strictes partout, alignées en permanence

- **Description** : modules et envs déclarent la même contrainte précise (ex : `ovh = "= 0.49.0"` partout).
- **Pour** : reproductibilité maximale, jamais de surprise.
- **Contre** : chaque mise à jour de provider doit être propagée dans tous les modules ET tous les envs simultanément, friction énorme à l'évolution.
- **Coût** : maintenance bloquante.

### Option 2 : Pas de contraintes dans les modules, contraintes uniquement dans les envs

- **Description** : `modules/*/versions.tf` ne déclare aucune contrainte (juste `required_providers` avec source), seuls les envs pinnent.
- **Pour** : modules ultra-flexibles.
- **Contre** : un module utilisé hors des envs du projet (ex : import dans un autre repo) n'a aucune garantie de compatibilité provider, perte de signal sur les versions testées.
- **Coût** : risque qualité sur la portabilité des modules.

### Option 3 : Contraintes larges dans les modules, contraintes précises dans les envs (avec lock file commité)

- **Description** :
  - **Modules** : contraintes en `~> X.Y` (large : major + minor compatible)
  - **Envs** : mêmes contraintes en `~> X.Y` aussi, plus le `.terraform.lock.hcl` commité qui pinne la version exacte
  - L'intersection contraintes module × contraintes env doit être non vide
- **Pour** : modules réutilisables sans étrangler la version, envs reproductibles via lock file, évolution graduelle (bumper le `~>` quand on veut tester une nouvelle minor).
- **Contre** : toujours nécessaire de vérifier que les contraintes module et env intersectent.

## Décision

Nous retenons **l'Option 3 — modules souples (`~> X.Y`), envs avec lock file commité**.

C'est le pattern standard recommandé par HashiCorp pour les projets multi-modules. Les modules déclarent un range compatible (`~> 0.46` accepte `0.46.x` à `0.99.x`), les envs choisissent une version précise via le lock file. Lorsqu'on veut bumper une version majeure côté module, on aligne aussi les envs, puis `terraform init -upgrade` régénère le lock.

**Règle de revue** : avant de merger un changement de `versions.tf` dans un module, vérifier que tous les envs qui utilisent ce module ont des contraintes compatibles.

## Conséquences

### Positives

- Modules réutilisables tels quels sans casser la compatibilité
- Envs reproductibles en CI / sur d'autres machines (lock file commité)
- Évolution graduelle des versions providers (un env à la fois si besoin)
- Détection précoce des incompatibilités via `terraform init`

### Négatives / Coûts

- Discipline requise sur la cohérence des contraintes module/env
- Le lock file dans chaque env peut diverger entre envs (différentes patch versions par env), ce qui est en général OK mais à surveiller
- Tout changement de `versions.tf` dans un module exige un `terraform init -upgrade` puis commit du lock file dans les envs concernés

### Neutres / À surveiller

- Pour automatiser la cohérence, envisager `tflint` ou un script CI qui valide l'intersection
- Si on adopte Terragrunt ou un générateur, repenser le pattern (Terragrunt centralise les versions)

## Alternatives non explorées (et pourquoi)

- **Terraform Cloud / Enterprise version sets** : surdimensionné pour le périmètre actuel, lock-in HCP.
- **Submodule git pour les `versions.tf`** : couplage trop rigide, anti-pattern Terraform.

## Références

- [Terraform — Provider Version Constraints](https://developer.hashicorp.com/terraform/language/providers/requirements#version-constraints)
- Commit `55249a7` — premier alignement des contraintes modules ↔ envs
