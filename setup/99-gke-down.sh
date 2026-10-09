#!/usr/bin/env bash
# Détruit proprement le cluster GKE du J3.
#
# Pourquoi pas un simple « terraform destroy » ? Sur Kapsule, delete_additional_resources
# emporte aussi les load balancers et les disques créés par Kubernetes. Sur GKE, rien de
# tel : un load balancer (Service) ou un disque (PVC) encore présent au moment où le
# cluster disparaît peut rester orphelin… et facturé. On les fait donc supprimer par
# Kubernetes lui-même, AVANT de détruire le cluster.
cd "$(dirname "$0")/.." || exit 1
source lib/demo.sh
VITESSE=0
export SANS_PAUSE=1
export ATTENTE_MAX="${ATTENTE_MAX-300}"   # un load balancer Google met une à deux minutes à disparaître

titre "GKE — destruction propre"
exiger kubectl terraform gcloud
export KUBECONFIG="$PWD/terraform-gke/kubeconfig.yaml"

if [ -f "$KUBECONFIG" ] && [ "$(type_cluster)" = "gke" ]; then
  # 1. ArgoCD d'abord : sinon il recrée ce qu'on supprime.
  silence "kubectl delete ns argocd --ignore-not-found --wait=true --timeout=180s"
  ok "ArgoCD retiré (il ne recréera plus rien)"

  # 2. Tous les namespaces applicatifs : leurs Services LoadBalancer et leurs PVC partent
  #    avec eux, et GKE supprime les load balancers et les disques correspondants.
  NAMESPACES=$(kubectl get ns -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' \
    | grep -vE '^(default|kube-.*|gke-.*|gmp-.*)$')
  if [ -n "$NAMESPACES" ]; then
    note "suppression : $(echo $NAMESPACES)"
    kubectl delete ns $NAMESPACES --wait=true --timeout=300s >/dev/null 2>&1
  fi
  attendre_que "plus aucun Service LoadBalancer" \
    "[ -z \"\$(kubectl get svc -A -o jsonpath='{.items[?(@.spec.type==\"LoadBalancer\")].metadata.name}')\" ]"
  attendre_que "plus aucun volume persistant" \
    "[ -z \"\$(kubectl get pv -o name)\" ]"
else
  note "pas de cluster GKE joignable : on passe directement à terraform destroy"
fi

# 3. Le cluster, le pool, le réseau, le registre.
terraform -chdir=terraform-gke destroy -auto-approve || { ko "terraform destroy en échec"; exit 1; }
ok "infrastructure détruite"

# 4. Vérification : rien d'orphelin chez Google.
DISQUES=$(gcloud compute disks list --filter="name~^pvc-" --format="value(name)" 2>/dev/null)
REGLES=$(gcloud compute forwarding-rules list --format="value(name)" 2>/dev/null)
if [ -z "$DISQUES$REGLES" ]; then
  ok "aucun disque ni load balancer orphelin"
else
  ko "ressources restantes — à supprimer dans la console (Compute Engine → Disques, Services réseau → Équilibrage de charge) :"
  printf '     %s\n' $DISQUES $REGLES
fi
