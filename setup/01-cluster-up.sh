#!/usr/bin/env bash
# Monte le cluster local de la formation : 2 nœuds, un vrai CNI, un Ingress maintenu.
cd "$(dirname "$0")/.." || exit 1
source lib/demo.sh
VITESSE=0

PROFIL="${PROFIL-ccs}"
K8S_VERSION="${K8S_VERSION-v1.34.0}"
MEMOIRE="${MEMOIRE-6g}"
CPUS="${CPUS-4}"

titre "Cluster local Minikube — profil « $PROFIL »"
exiger minikube kubectl helm

note "2 nœuds : indispensable pour les démonstrations de placement (taints, anti-affinité)"
note "CNI Calico : sans lui, les Network Policies sont acceptées… mais ignorées"
note "Sur Mac, ces ${MEMOIRE} sont pris à Docker Desktop : il lui en faut au moins 8 au total"

minikube start -p "$PROFIL" \
  --nodes=2 \
  --cni=calico \
  --cpus="$CPUS" --memory="$MEMOIRE" \
  --kubernetes-version="$K8S_VERSION" \
  --addons=metrics-server || { ko "démarrage du cluster impossible"; exit 1; }

kubectl config use-context "$PROFIL" >/dev/null 2>&1

attendre_que "les nœuds passent Ready" \
  "[ \$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready ') -ge 2 ]"
attendre_que "Calico est en place" \
  "kubectl -n kube-system get pods -l k8s-app=calico-node --no-headers 2>/dev/null | grep -q Running"

# --- étiquettes de nœuds utilisées par les manifests ---
PREMIER=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
SECOND=$(kubectl get nodes -o jsonpath='{.items[1].metadata.name}')
kubectl label node "$PREMIER" stockage=oui --overwrite >/dev/null
kubectl label node "$SECOND" zone=paiement --overwrite >/dev/null
ok "nœud $PREMIER → stockage=oui (le volume local y vit)"
ok "nœud $SECOND → zone=paiement (quai réservé pour la démo des taints)"

# --- Ingress : Traefik, et pas ingress-nginx (retiré du projet en mars 2026) ---
helm repo add traefik https://traefik.github.io/charts >/dev/null 2>&1
helm repo update >/dev/null 2>&1
helm upgrade --install traefik traefik/traefik \
  --namespace traefik --create-namespace \
  --set service.type=NodePort \
  --set ports.web.nodePort=30080 \
  --set ingressClass.enabled=true \
  --set ingressClass.isDefaultClass=true >/dev/null || note "Traefik non installé (réseau ?) — les démos marchent en port-forward"

attendre_que "Traefik est prêt" "kubectl -n traefik get deploy traefik -o jsonpath='{.status.readyReplicas}' | grep -q 1"

IP=$(minikube -p "$PROFIL" ip)
echo
ok "Cluster prêt. Nœud : $IP"
echo
if [ "$(uname -s)" = "Darwin" ]; then
  note "Sur macOS, le driver Docker fait tourner les nœuds dans une machine virtuelle :"
  note "l'IP $IP n'est PAS joignable depuis le Mac. Un NodePort ne suffit donc pas."
  echo
  echo "   Une fois pour toutes, dans /etc/hosts — sur la boucle locale :"
  echo "      echo '127.0.0.1 shopix.local' | sudo tee -a /etc/hosts"
  echo
  echo "   Puis, dans un terminal dédié pendant la session :"
  echo "      ./setup/07-acces.sh          → http://shopix.local:8888"
else
  echo "   Ajoutez une fois pour toutes cette ligne à /etc/hosts :"
  echo "      $IP  shopix.local"
  echo "   (commande : echo \"$IP shopix.local\" | sudo tee -a /etc/hosts)"
  echo "   La boutique sera alors sur http://shopix.local:30080"
fi
echo
echo "   Suite :  ./setup/02-images.sh  &&  ./setup/03-deployer.sh"
