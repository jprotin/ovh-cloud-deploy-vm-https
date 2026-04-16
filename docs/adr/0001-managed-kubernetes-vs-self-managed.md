# 0001 — Choix de Managed Kubernetes (MKS) plutôt que K8s self-managed

- **Status** : accepted
- **Date** : 2026-04-16
- **Auteur(s)** : protin
- **Tags** : architecture, kubernetes, ops

## Contexte

La landing zone OVHcloud doit pouvoir héberger des workloads Kubernetes pour des cas d'usage sandbox / dev / démo. L'équipe est en mode solo (un seul opérateur), avec une bande passante ops réduite. Les besoins sont :

- déployer rapidement un cluster fonctionnel sur OVHcloud Public Cloud ;
- minimiser la dette d'exploitation (patching, upgrades, scaling du control plane) ;
- garder un coût mensuel maîtrisé pour des environnements éphémères ;
- pouvoir déployer en multi-AZ pour démontrer la HA.

Les workloads attendus sont peu critiques (démos, tests fonctionnels), ce qui réduit l'exigence sur la maîtrise fine du control plane.

## Options envisagées

### Option 1 : OVHcloud Managed Kubernetes Service (MKS)

- **Description** : le control plane Kubernetes est géré par OVHcloud (HA inclus, mises à jour gérées). On ne provisionne que les workers.
- **Pour** : control plane gratuit, intégration native OVH (load balancer Octavia, réseau privé), upgrades managées, multi-AZ disponible en région 3AZ (EU-WEST-PAR), zéro maintenance plane.
- **Contre** : versions Kubernetes limitées à celles que supporte OVH, control plane non customisable (pas d'admission webhooks au niveau control plane, pas de modification de la kube-apiserver flags).
- **Coût** : control plane = 0 €. Worker nodes facturés au tarif Public Cloud standard.

### Option 2 : Kubernetes self-managed (kubeadm) sur VMs OVH

- **Description** : provisionner des VMs OpenStack et installer Kubernetes via kubeadm + scripts cloud-init.
- **Pour** : maîtrise totale (versions, flags, plugins), pas de lock-in OVH au-delà de l'IaaS, possibilité d'expérimenter sur la stack control plane.
- **Contre** : il faut maintenir le control plane (etcd, kube-apiserver, scheduler, controller-manager), gérer les upgrades, gérer la HA du control plane (3 masters minimum), plus de surface d'attaque à durcir.
- **Coût** : 3 VMs control plane HA + workers = surcoût significatif (~25-40 €/mois rien que pour le plane).

### Option 3 : K3s ou autre distribution légère self-managed

- **Description** : K3s sur 1-3 VMs, distribution légère.
- **Pour** : très simple à installer, faible footprint mémoire, idéal pour sandbox solo.
- **Contre** : moins représentatif d'une stack production, pas le même comportement que K8s vanilla sur certains aspects (CNI, ingress par défaut), maintenance toujours à la charge de l'opérateur.
- **Coût** : 1 petite VM suffit (~5 €/mois) mais peu pertinent en multi-AZ.

## Décision

Nous retenons **l'Option 1 — OVHcloud MKS**.

Le contexte sandbox + opérateur solo + besoin de démo HA multi-AZ aligne parfaitement avec la proposition de valeur du managé : gratuité du plane, multi-AZ disponible (en région 3AZ), aucune maintenance ops, intégration native avec le LoadBalancer Octavia et le réseau privé. Le sacrifice sur la customisation fine du plane est non bloquant pour les cas d'usage visés.

## Conséquences

### Positives

- Coût plancher = 0 € pour le control plane, on ne paie que les workers
- Aucune maintenance du plane (upgrades, etcd, certificats gérés par OVH)
- Multi-AZ disponible immédiatement en EU-WEST-PAR
- Intégration directe avec les services Public Cloud (LB Octavia, réseaux privés)

### Négatives / Coûts

- Lock-in OVHcloud sur le plane (pas de portabilité directe, mais les manifests K8s restent portables)
- Versions Kubernetes contraintes par le calendrier OVH
- Pas de visibilité fine sur les composants du plane (logs, metrics, configurations)
- Région 3AZ exige `private_network_id` + `nodes_subnet_id` (contrainte spécifique gérée dans le module `mks/`)

### Neutres / À surveiller

- Évolutions des tarifs OVH MKS (control plane reste-t-il gratuit ?)
- Délai de support des nouvelles versions Kubernetes par OVH
- Si on devait passer à des workloads critiques, réévaluer (admission webhooks custom, audit logs, etc.)

## Alternatives non explorées (et pourquoi)

- **GKE / EKS / AKS** : exclus car le projet est explicitement OVHcloud (souveraineté, contraintes de coût européen).
- **Rancher / OpenShift on OVH** : surcouche inutile pour un sandbox solo, ajoute une stack à maintenir.

## Références

- [OVHcloud Managed Kubernetes — documentation officielle](https://help.ovhcloud.com/csm/fr-public-cloud-kubernetes-getting-started)
- ADR 0006 — Choix de région (Paris 3AZ vs SBG mono-AZ)
