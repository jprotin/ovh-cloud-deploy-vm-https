# Démo Kubernetes Multi-AZ

Déploiement nginx qui affiche la zone de disponibilité (AZ) servant chaque requête.

## Fonctionnement

```
  Internet
     │
     ▼
  ┌────────────────────────────┐
  │ Service LoadBalancer       │  ← Octavia LB OVHcloud (auto-provisionné)
  │ IP publique : à déterminer │
  └────────────────────────────┘
     │ load balance
     ├────────┬────────┬────────┐
     ▼        ▼        ▼        ▼
   Pod      Pod      Pod      Pod ...
   AZ-a     AZ-b     AZ-a     AZ-b
   (bleu)   (vert)   (bleu)   (vert)
```

Chaque pod :

1. Au démarrage, un **init container** (`bitnami/kubectl`) utilise un **ServiceAccount RBAC** pour lire le label `topology.kubernetes.io/zone` du node qui l'héberge
2. Génère une `index.html` colorée selon la zone (bleu = a, vert = b, rouge = c)
3. Le container **nginx** la sert sur le port 80

Le **`Service type=LoadBalancer`** provoque la création automatique d'un **Octavia Public Cloud LB** chez OVHcloud, avec une IP publique routée vers les pods.

## Déploiement

```bash
# Via infra.sh (recommandé)
./infra.sh deploy-demo -e mks-sandbox-par

# Ou manuellement
export KUBECONFIG=envs/mks-sandbox-par/kubeconfig.yaml
kubectl apply -f examples/k8s-multi-az-demo/
```

## Accès

```bash
# Récupérer l'IP publique du LoadBalancer (patienter 1-2 min après le deploy)
kubectl get svc zone-demo

# NAME        TYPE           CLUSTER-IP     EXTERNAL-IP      PORT(S)
# zone-demo   LoadBalancer   10.x.x.x       XX.XX.XX.XX      80:xxxxx/TCP
```

Puis ouvrir `http://<EXTERNAL-IP>` dans un navigateur et rafraîchir pour voir la rotation du load balancing entre les zones.

## Composants

| Fichier              | Rôle                                                                  |
| -------------------- | --------------------------------------------------------------------- |
| `00-rbac.yaml`       | ServiceAccount + ClusterRole + ClusterRoleBinding pour lire les nodes |
| `01-configmap.yaml`  | Script shell qui génère l'HTML avec la zone                           |
| `02-deployment.yaml` | Deployment nginx + init container, avec anti-affinity inter-AZ        |
| `03-service.yaml`    | Service LoadBalancer → IP publique OVHcloud                           |

## Destruction

```bash
./infra.sh destroy-demo -e mks-sandbox-par

# Ou manuellement
kubectl delete -f examples/k8s-multi-az-demo/
```

**Important** : supprimer la démo **avant** de détruire le cluster, sinon l'Octavia LB reste orphelin (facturation continue).
