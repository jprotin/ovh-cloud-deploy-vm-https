# 0006 — Choix de région : Paris 3AZ (HA payant) vs SBG mono-AZ (cheap)

- **Status** : accepted
- **Date** : 2026-04-16
- **Auteur(s)** : protin
- **Tags** : architecture, coût, HA, ovhcloud

## Contexte

OVHcloud Public Cloud propose plusieurs régions, dont les caractéristiques diffèrent significativement :

- **SBG5, GRA, DE, UK, BHS** — régions dites « 1AZ » : une seule zone de disponibilité, moins chères, plan Discovery (entrée de gamme) éligible.
- **EU-WEST-PAR** (et autres « 3AZ ») — régions multi-AZ : 3 zones indépendantes au sein de la même région, exigent un plan **Essentials ou supérieur** (payant), ressources plus chères mais HA réelle.

Le projet vise deux types d'usage :

- **Démos rapides** (VM Nginx, MKS mono-node) : on veut le coût le plus bas, la HA n'a aucune valeur.
- **Démos K8s HA / multi-AZ** : on veut démontrer qu'un cluster MKS peut survivre à la perte d'une AZ, ce qui exige une région 3AZ.

Pendant le bootstrap, on a tenté de provisionner MKS en EU-WEST-PAR sur un compte Discovery → erreur claire d'OVH : `plan is not compatible with this region`. Le passage en plan Essentials a débloqué.

## Options envisagées

### Option 1 : Tout en SBG mono-AZ

- **Description** : forcer toutes les démos sur SBG (ou équivalent 1AZ) pour minimiser le coût.
- **Pour** : coût minimal, plan Discovery éligible, simplicité.
- **Contre** : impossible de démontrer la HA multi-AZ, MKS reste mono-zone (un nœud / une AZ tombe = service down), pas représentatif des architectures cloud modernes.
- **Coût** : ~5 €/mois pour une VM, ~5-10 €/mois pour un MKS 1 node mono-AZ.

### Option 2 : Tout en Paris 3AZ

- **Description** : tout déployer en EU-WEST-PAR pour la HA et la cohérence.
- **Pour** : pattern unique, démos HA partout.
- **Contre** : surcoût significatif sur les démos qui n'ont pas besoin de HA (VM seule en multi-AZ n'a pas grand sens), exige un plan payant en permanence, plus de friction côté quotas et IPs.
- **Coût** : ~36 €/mois pour 2 workers MKS multi-AZ, plus surcoûts plan Essentials.

### Option 3 : Les deux régions supportées, choix par env

- **Description** :
  - `envs/sandbox-sbg5/` (et `sandbox-par/` avec `enable_vm`) → SBG5 par défaut, démos cheap
  - `envs/mks-sandbox-par/` → EU-WEST-PAR multi-AZ, démos HA
  - L'opérateur choisit l'env selon le besoin
- **Pour** : couvre tous les cas d'usage avec le coût optimal pour chacun, expose explicitement le trade-off coût/HA dans le nom de l'env.
- **Contre** : deux contextes à maintenir (ex : module MKS doit gérer le `nodes_subnet_id` requis en 3AZ et optionnel en 1AZ), deux openrc à gérer (ADR 0004), deux configurations à tester.

## Décision

Nous retenons **l'Option 3 — supporter les deux régions, choix par env**.

Le projet est une landing zone de démo : le but est précisément d'illustrer les options offertes par OVHcloud, pas d'imposer un choix unique. Les noms d'env (`sandbox-sbg5`, `mks-sandbox-par`) rendent le choix explicite. Le surcoût des envs Paris 3AZ est assumé pour les démos HA, et le plan Essentials peut être désactivé entre deux démos pour limiter la facturation continue.

## Conséquences

### Positives

- Démos cheap disponibles via SBG5 (~5 €/mois, plan Discovery)
- Démos HA disponibles via EU-WEST-PAR (multi-AZ réel, ~36-50 €/mois)
- Le module MKS supporte les deux modes (avec / sans `nodes_subnet_id`)
- Pattern transposable à d'autres régions (1AZ ou 3AZ) en ajoutant un env

### Négatives / Coûts

- Le module MKS doit gérer explicitement le cas 3AZ (variable `nodes_subnet_id`, doc dans le module)
- Deux openrc à maintenir (cf. ADR 0004)
- Risque de tester un env et oublier qu'il faut un plan payant pour PAR (erreur explicite remontée par OVH, donc gérable)
- Pas de matrice automatique « 1 démo = 2 régions testées en parallèle » ; chaque région est testée indépendamment

### Neutres / À surveiller

- Si OVH étend les régions 3AZ sans surcoût plan, on pourra basculer plus largement vers 3AZ
- Si on ajoute d'autres types d'envs (DBaaS, object storage), évaluer à chaque fois le besoin HA réel
- Coût mensuel à monitorer : un env Paris oublié peut grimper vite

## Alternatives non explorées (et pourquoi)

- **Régions hors UE (BHS Canada, SGP Singapour)** : exclues car le projet privilégie la souveraineté UE.
- **Cross-region (un service en SBG, un en PAR)** : pas de cas d'usage actuellement, ajouterait de la latence inter-régions.

## Références

- [OVHcloud — Régions Public Cloud et zones de disponibilité](https://help.ovhcloud.com/csm/fr-public-cloud-compute-regions-availability)
- [OVHcloud — Plans Public Cloud](https://www.ovhcloud.com/fr/public-cloud/prices/)
- ADR 0001 — Choix MKS managé (motivation HA)
- ADR 0004 — Stratégie openrc par région (conséquence de ce choix)
