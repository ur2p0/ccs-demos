#!/usr/bin/env bash
# Remet l'environnement dans l'état de départ, entre deux démonstrations
# ou entre deux sessions. Ne détruit jamais le cluster (voir setup/99-cluster-down.sh).
cd "$(dirname "$0")/.." || exit 1
source lib/demo.sh
VITESSE=0
NS="${NS-shopix}"

cible="${1---tout}"
titre "Remise à zéro ($cible)"

nettoyer_docker() {
  note "containers et volumes de la démonstration Docker"
  silence "docker rm -f shopix-api shopix-front shopix-bride 2>/dev/null"
  silence "docker volume rm shopix-donnees 2>/dev/null"
  silence "docker network rm shopix 2>/dev/null"
  ok "Docker nettoyé"
}

nettoyer_k8s() {
  note "objets créés pendant les démonstrations"
  # On énumère 01 à 09 : le générateur de trafic (10) et le HPA (11) servent au J3
  # et ne doivent PAS être détruits par une remise à zéro du J2.
  for _f in k8s/demos/0*.yaml k8s/demos/tools.yaml; do
    silence "kubectl -n $NS delete -f $_f --ignore-not-found"
  done
  silence "kubectl -n $NS delete netpol --all"
  silence "kubectl -n $NS delete job facturation --ignore-not-found"
  silence "kubectl label ns $NS pod-security.kubernetes.io/enforce=baseline --overwrite"
  for n in $(kubectl get nodes -o name 2>/dev/null); do
    silence "kubectl taint $n paiement=true:NoSchedule- 2>/dev/null"
  done
  silence "kubectl -n $NS scale deploy shopix-api --replicas=2"
  silence "kubectl -n $NS scale deploy shopix-front --replicas=2"
  silence "kubectl -n $NS exec deploy/shopix-api -- wget -q -O- http://127.0.0.1:8080/admin/reparer"
  ok "Cluster remis dans l'état de départ"
}

nettoyer_j3() {
  note "objets du J3 (générateur de trafic, HPA) et dérive GitOps"
  silence "kubectl -n $NS delete -f k8s/demos/10-charge.yaml --ignore-not-found"
  silence "kubectl -n $NS delete -f k8s/demos/11-hpa.yaml --ignore-not-found"
  silence "kubectl -n $NS scale deploy shopix-front --replicas=2"
  ok "J3 remis dans l'état de départ"
}

vider_donnees() {
  note "vidage du volume de commandes (repartir d'une boutique neuve)"
  silence "kubectl -n $NS exec deploy/shopix-commandes -- rm -f /data/commandes.json"
  silence "kubectl -n $NS rollout restart deploy shopix-commandes"
  ok "Commandes effacées"
}

case "$cible" in
  --docker) nettoyer_docker ;;
  --j2|--k8s) nettoyer_k8s ;;
  --j3) nettoyer_j3 ;;
  --donnees) vider_donnees ;;
  --tout)
    nettoyer_docker
    nettoyer_k8s
    nettoyer_j3
    vider_donnees
    note "le générateur de trafic du J3 a été supprimé — à relancer le J3 au matin :"
    note "   kubectl apply -f k8s/demos/10-charge.yaml"
    echo
    kubectl -n "$NS" get pods 2>/dev/null
    ;;
  *)
    echo "usage : $0 [--tout | --docker | --j2 | --j3 | --donnees]"
    exit 1
    ;;
esac
