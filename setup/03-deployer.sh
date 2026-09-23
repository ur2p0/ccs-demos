#!/usr/bin/env bash
# Déploie Shopix dans le cluster (état de départ de toutes les démonstrations).
cd "$(dirname "$0")/.." || exit 1
source lib/demo.sh
VITESSE=0
PROFIL="${PROFIL-ccs}"

titre "Déploiement de Shopix"
exiger kubectl

kubectl apply -k k8s/overlays/minikube || { ko "déploiement en échec"; exit 1; }
attendre_que "le front est prêt" "kubectl -n shopix get deploy shopix-front -o jsonpath='{.status.readyReplicas}' | grep -q 2"
attendre_que "l'API est prête" "kubectl -n shopix get deploy shopix-api -o jsonpath='{.status.readyReplicas}' | grep -q 2"
attendre_que "le service de commandes est prêt" "kubectl -n shopix get deploy shopix-commandes -o jsonpath='{.status.readyReplicas}' | grep -q 1"

kubectl -n shopix get pods -o wide
echo
if [ "$(uname -s)" = "Darwin" ]; then
  ok "Boutique : lancez ./setup/07-acces.sh dans un terminal dédié → http://shopix.local:8888"
  note "sur macOS l'IP du nœud n'est pas routable : le tunnel vers Traefik s'en charge"
else
  IP=$(minikube -p "$PROFIL" ip 2>/dev/null)
  ok "Boutique : http://shopix.local:30080   (si /etc/hosts contient « $IP shopix.local »)"
fi
note "Secours, sans Ingress : kubectl -n shopix port-forward svc/shopix-front 8080:8080"
