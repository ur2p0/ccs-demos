#!/usr/bin/env bash
# Ouvre l'accès à Grafana et à ArgoCD depuis le navigateur du Mac (J3).
#
# Même raison d'être que 07-acces.sh : avec le driver Docker sur macOS, l'IP du
# nœud Minikube vit dans une machine virtuelle et n'est pas routable depuis
# macOS. Les NodePort 30300 et 30800 ne répondent donc pas, malgré les
# apparences. Sur Linux, ce script est inutile.
#
#   ./setup/08-acces-j3.sh        laisse tourner dans un terminal dédié
#   PORT_GRAFANA=3001 ./setup/08-acces-j3.sh
#
# À lancer EN PLUS de 07-acces.sh (la boutique), dans un autre terminal.
cd "$(dirname "$0")/.." || exit 1
source lib/demo.sh
VITESSE=0
PORT_GRAFANA="${PORT_GRAFANA-3000}"
PORT_ARGOCD="${PORT_ARGOCD-8080}"

titre "Accès J3 — Grafana et ArgoCD"
exiger kubectl

_pids=""
_motifs=""

arreter() {
  printf "\n"
  for p in $_pids; do kill "$p" 2>/dev/null; done
  for m in $_motifs; do pkill -f "port-forward svc/$m" 2>/dev/null; done
  note "tunnels fermés"
  exit 0
}
trap arreter INT TERM

# tunnel <namespace> <service> <port_local> <port_distant> <libellé>
tunnel() {
  local ns="$1" svc="$2" pl="$3" pd="$4" lib="$5"
  if [ -z "$svc" ] || ! kubectl -n "$ns" get svc "$svc" >/dev/null 2>&1; then
    ko "$lib : service introuvable dans le namespace $ns — pile non installée"
    return 1
  fi
  if lsof -nP -iTCP:"$pl" -sTCP:LISTEN >/dev/null 2>&1; then
    ko "$lib : le port $pl est déjà occupé sur le Mac"
    note "   relancez avec un autre port, ex. PORT_GRAFANA=3001 $0"
    return 1
  fi
  (
    while true; do
      kubectl -n "$ns" port-forward "svc/$svc" "$pl:$pd" >/dev/null 2>&1
      sleep 2
    done
  ) &
  _pids="$_pids $!"
  _motifs="$_motifs $svc"
  ok "$lib : http://localhost:$pl"
  return 0
}

# Le nom du service Grafana dépend du nom de la release Helm : on le découvre.
SVC_GRAFANA=$(kubectl -n observabilite get svc -l app.kubernetes.io/name=grafana \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
PORT_SVC_GRAFANA=$(kubectl -n observabilite get svc -l app.kubernetes.io/name=grafana \
  -o jsonpath='{.items[0].spec.ports[0].port}' 2>/dev/null)

echo
tunnel observabilite "$SVC_GRAFANA" "$PORT_GRAFANA" "${PORT_SVC_GRAFANA:-80}" "Grafana   (admin / shopix)"
tunnel argocd        argocd-server  "$PORT_ARGOCD"  80                        "ArgoCD    (admin / voir 05-argocd.sh)"

if [ -z "$_pids" ]; then
  echo
  ko "aucun tunnel ouvert — lancez ./setup/04-observabilite.sh et ./setup/05-argocd.sh"
  exit 1
fi

echo
note "laissez ce terminal ouvert pendant toute la journée · Ctrl-C pour arrêter"
note "les tunnels se relancent tout seuls s'ils tombent"
wait
