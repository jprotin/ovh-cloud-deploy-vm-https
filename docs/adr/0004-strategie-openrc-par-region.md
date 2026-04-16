# 0004 — Stratégie openrc séparée par région OVHcloud

- **Status** : accepted
- **Date** : 2026-04-16
- **Auteur(s)** : protin
- **Tags** : sécurité, secrets, ops, openstack

## Contexte

Sur OVHcloud Public Cloud, les credentials OpenStack (utilisateur, password, projet) ne sont **pas mutualisés entre régions**. Chaque région (SBG, GRA, DE, EU-WEST-PAR...) a son propre projet OpenStack avec ses propres comptes utilisateur, et donc son propre fichier `openrc.sh` téléchargé depuis le Manager OVH (`Public Cloud → Users & Roles → OpenRC`).

Pendant le bootstrap, on a découvert ce point en dur : un déploiement Paris configuré avec les `OS_*` d'un openrc SBG renvoyait des erreurs d'authentification opaques. Il faut donc :

- savoir clairement quel `OS_PASSWORD` correspond à quelle région ;
- ne pas se tromper de fichier au moment de sourcer ;
- ne jamais commiter ces fichiers (ils contiennent des credentials en clair) ;
- automatiser le sourcing dans `infra.sh` pour éviter l'erreur humaine.

## Options envisagées

### Option 1 : Un seul `openrc.sh` "courant", à régénérer manuellement avant chaque changement de région

- **Description** : l'utilisateur source `openrc.sh`, qui est remplacé manuellement quand on change de région.
- **Pour** : un seul nom de fichier à connaître.
- **Contre** : le fichier change selon la dernière région utilisée → erreur fréquente (sourcing du mauvais fichier sans s'en rendre compte), pas de trace de quelle région est active.
- **Coût** : zéro automatisation possible.

### Option 2 : Variables `OS_*` exportées dans le shell de l'utilisateur (`.bashrc`, direnv...)

- **Description** : pas de fichier intermédiaire, l'utilisateur exporte les variables directement.
- **Pour** : pas de fichier à manipuler.
- **Contre** : multi-régions impossible sans gymnastique (préfixer chaque variable, scripts de switch...), `direnv` ne résout pas le problème par projet, plus de transparence sur ce qui est chargé.
- **Coût** : friction multi-régions élevée.

### Option 3 : Un fichier `openrc_<REGION>.sh` par région, sourcing automatique selon l'env cible

- **Description** : `openrc_PAR.sh`, `openrc_SBG.sh` (et potentiellement `openrc_GRA.sh` plus tard), tous gitignorés. `infra.sh` détecte la région de l'env (via `terraform.tfvars` ou nom de l'env) et source automatiquement le bon fichier avant chaque opération Terraform.
- **Pour** : impossible de se tromper de fichier, scalable (ajouter une région = ajouter un fichier), automatisé, traçable (le script affiche quel openrc il source).
- **Contre** : un fichier par région à maintenir et à régénérer si rotation des credentials.

## Décision

Nous retenons **l'Option 3 — un fichier openrc par région + sourcing auto**.

Le pattern `openrc_<REGION>.sh` est naturel (suit la convention OVH du fichier généré), le sourcing automatique élimine l'erreur humaine, et la séparation par région évite les fuites croisées de credentials. Le `.gitignore` couvre `openrc*.sh` pour éviter tout commit accidentel. La détection région dans `infra.sh` se fait par priorité : `terraform.tfvars` → nom de l'env (`*par*` → PAR, `*sbg*` → SBG).

## Conséquences

### Positives

- Aucune erreur possible sur "quel openrc est actif"
- Multi-régions natif (ajouter une région = ajouter un fichier)
- `infra.sh` reste self-contained : `./infra.sh deploy -e mks-sandbox-par` source le bon openrc tout seul
- Rotation des credentials = simple remplacement d'un fichier

### Négatives / Coûts

- N fichiers à maintenir (un par région utilisée)
- Risque de divergence si un fichier est mis à jour et pas l'autre (mais sans impact, ils sont indépendants par région)
- Le sourcing automatique peut masquer une mauvaise config si l'utilisateur s'attend à devoir sourcer manuellement (à documenter)

### Neutres / À surveiller

- Si on adopte un secret manager (Vault, OVH KMS, sops), reconsidérer pour ne plus avoir les passwords en clair sur disque
- Si on multiplie les comptes utilisateurs OpenStack par région (multi-équipes), le pattern actuel reste OK mais le nommage devra évoluer (`openrc_PAR_user1.sh` vs `_user2.sh`)

## Alternatives non explorées (et pourquoi)

- **HashiCorp Vault** ou **OVH Secret Manager** : surdimensionné pour un projet sandbox solo. Pertinent si plusieurs opérateurs ou environnement critique.
- **sops + git-crypt** : possible mais ajoute une étape de chiffrement / déchiffrement, valeur faible vs. simple gitignore en solo.

## Références

- ADR 0006 — Choix de région (complète celui-ci sur le pourquoi multi-régions)
- `infra.sh` — fonction `source_openrc()` qui implémente la détection automatique
- `.gitignore` — pattern `openrc*.sh`
