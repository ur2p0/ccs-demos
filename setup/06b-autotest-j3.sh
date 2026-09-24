#!/usr/bin/env bash
# Vérifie les deux piles du J3 — observabilité et GitOps — avant la séance.
# Complément de 06-autotest.sh, qui ne couvre que le J1 et le J2.
#
#   ./setup/06b-autotest-j3.sh
#
# À lancer la veille du J3, après 04-observabilite.sh, 05-argocd.sh et
# 05b-depot-gitops.sh. Compter 2 minutes.
cd "$(dirname "$0")/.." || exit 1
source lib/demo.sh
VITESSE=0
SANS_PAUSE=1
NS="${NS-shopix}"
MDP_GRAFANA="${MDP_GRAFANA-shopix}"
AUTH="Authorization: Basic $(printf 'admin:%s' "$MDP_GRAFANA" | base64 | tr -d '\n')"

REUSSIS=0; ECHOUES=0; IGNORES=0
RESUME=""

tester() {
  local libelle="$1"; shift
  printf "  %-58s" "$libelle"
  ( set +o pipefail; eval "$@" ) >/tmp/ccs-autotest-j3.log 2>&1
  local code=$?
  if [ $code -eq 0 ]; then
    printf "%s✔ ok%s\n" "$C_OK" "$C_RAZ"
    REUSSIS=$((REUSSIS + 1)); RESUME="$RESUME\n  ✔  $libelle"
  else
    printf "%s✘ ÉCHEC%s\n" "$C_KO" "$C_RAZ"
    ECHOUES=$((ECHOUES + 1)); RESUME="$RESUME\n  ✘  $libelle"
    if [ -s /tmp/ccs-autotest-j3.log ]; then
      sed 's/^/        /' /tmp/ccs-autotest-j3.log | head -4
    else
      printf "        (aucune sortie · code de retour %s)\n" "$code"
    fi
  fi
}

ignorer() {
  printf "  %-58s%s— ignoré%s\n" "$1" "$C_GRIS" "$C_RAZ"
  IGNORES=$((IGNORES + 1)); RESUME="$RESUME\n  —  $1 (ignoré)"
}

patienter() {
  local max="$1"; shift
  local n=0
  while [ $n -lt "$max" ]; do
    ( set +o pipefail; eval "$@" ) >/dev/null 2>&1 && return 0
    sleep 2; n=$((n + 2))
  done
  return 1
}

titre "Autotest J3 — observabilité et GitOps"
exiger kubectl
annoncer_cluster

# Une NetworkPolicy oubliée empêcherait le Pod « tools » d'interroger l'API.
silence "kubectl -n $NS delete netpol --all"
silence "appliquer_demo k8s/demos/tools.yaml"
patienter 60 "kubectl -n $NS get pod tools -o jsonpath='{.status.phase}' | grep -q Running" \
  || { ko "le Pod « tools » ne démarre pas — impossible de tester depuis le cluster"; exit 1; }

# ══════════════════════════════════════════════ 1. la pile d'observabilité
etape 1 "Prometheus, Grafana, Loki"

OBS=oui
if ! kubectl get ns observabilite >/dev/null 2>&1; then
  OBS=non
  ignorer "pile d'observabilité (namespace absent — ./setup/04-observabilite.sh)"
fi

if [ "$OBS" = "oui" ]; then
tester "les Pods d'observabilité sont tous Running" \
  "! kubectl -n observabilite get pods --no-headers | grep -vE 'Running|Completed' | grep -q ."

tester "le ServiceMonitor de Shopix est posé" \
  "kubectl -n observabilite get servicemonitor shopix -o name | grep -q shopix"

# Le nom du service Prometheus dépend du chart ET de sa version. L'étiquette
# app.kubernetes.io/name=prometheus n'est pas posée par toutes les versions de
# kube-prometheus-stack : on essaie plusieurs pistes plutôt qu'une seule.
trouver_svc_prometheus() {
  local nom sel
  for sel in "app.kubernetes.io/name=prometheus" "app=kube-prometheus-stack-prometheus"; do
    nom=$(kubectl -n observabilite get svc -l "$sel" \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    [ -n "$nom" ] && { printf '%s' "$nom"; return 0; }
  done
  # par le nom, en écartant le service « operated » qui est sans adresse propre
  nom=$(kubectl -n observabilite get svc -o name 2>/dev/null | sed 's|service/||' \
    | grep -- '-prometheus$' | grep -v operated | head -1)
  [ -n "$nom" ] && { printf '%s' "$nom"; return 0; }
  # dernier recours : le service headless créé par l'opérateur
  kubectl -n observabilite get svc -l operated-prometheus=true \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}
SVC_PROM=$(trouver_svc_prometheus)
SVC_GRAF=$(kubectl -n observabilite get svc -l app.kubernetes.io/name=grafana \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
PORT_GRAF=$(kubectl -n observabilite get svc -l app.kubernetes.io/name=grafana \
  -o jsonpath='{.items[0].spec.ports[0].port}' 2>/dev/null)
note "services découverts : prometheus=${SVC_PROM:-INTROUVABLE} · grafana=${SVC_GRAF:-INTROUVABLE}:${PORT_GRAF:-?}"
if [ -z "$SVC_PROM" ]; then
  ko "service Prometheus introuvable — voici ce qu'il y a dans le namespace :"
  kubectl -n observabilite get svc --show-labels | sed 's/^/     /'
fi

# On provoque un peu de trafic, puis on laisse passer deux collectes.
silence "for i in 1 2 3 4 5 6 7 8 9 10; do kubectl -n $NS exec tools -- wget -q -T 3 -O /dev/null http://shopix-api:8080/api/produits; done"
PROM="http://$SVC_PROM.observabilite.svc.cluster.local:9090"
tester "Prometheus collecte les métriques de Shopix" \
  "patienter 60 \"kubectl -n $NS exec tools -- wget -q -T 5 -O- '$PROM/api/v1/query?query=shopix_request_duration_seconds_count' | grep -q '\\\"value\\\"'\""

GRAF="http://$SVC_GRAF.observabilite.svc.cluster.local:${PORT_GRAF:-80}"
tester "la source de données Prometheus a bien l'uid « prometheus »" \
  "patienter 60 \"kubectl -n $NS exec tools -- wget -q -T 5 --header='$AUTH' -O- '$GRAF/api/datasources/uid/prometheus' | grep -q prometheus\""

tester "le tableau de bord Shopix est provisionné dans Grafana" \
  "kubectl -n $NS exec tools -- wget -q -T 5 --header='$AUTH' -O- '$GRAF/api/dashboards/uid/shopix-ccs' | grep -q 'observabilit'"

if kubectl -n observabilite get svc loki >/dev/null 2>&1; then
  # Le sidecar peut mettre un moment à recharger le provisioning : on patiente.
  tester "la source de données Loki est déclarée (panneau Journaux)" \
    "patienter 90 \"kubectl -n $NS exec tools -- wget -q -T 5 --header='$AUTH' -O- '$GRAF/api/datasources/uid/loki' | grep -q loki\""
else
  ignorer "source de données Loki (Loki non installé)"
fi

if kubectl -n "$NS" get deploy shopix-charge >/dev/null 2>&1; then
  tester "le générateur de trafic tourne" \
    "[ \"\$(kubectl -n $NS get deploy shopix-charge -o jsonpath='{.status.readyReplicas}')\" != '' ]"
else
  ignorer "générateur de trafic (kubectl apply -f k8s/demos/10-charge.yaml)"
fi
fi   # fin du bloc observabilité

# ══════════════════════════════════════════════ 2. la pile GitOps
etape 2 "ArgoCD"

if ! kubectl -n argocd get deploy argocd-server >/dev/null 2>&1; then
  ignorer "ArgoCD (non installé — ./setup/05-argocd.sh)"
else
  tester "le serveur ArgoCD est prêt" \
    "[ \"\$(kubectl -n argocd get deploy argocd-server -o jsonpath='{.status.readyReplicas}')\" = 1 ]"
  tester "ArgoCD sert en HTTP (pas d'écran de certificat en salle)" \
    "kubectl -n argocd get cm argocd-cmd-params-cm -o jsonpath='{.data.server\\.insecure}' | grep -q true"

  if kubectl -n argocd get app shopix >/dev/null 2>&1; then
    tester "l'application shopix est Synced" \
      "kubectl -n argocd get app shopix -o jsonpath='{.status.sync.status}' | grep -q Synced"
    tester "l'application shopix est Healthy" \
      "patienter 90 \"kubectl -n argocd get app shopix -o jsonpath='{.status.health.status}' | grep -q Healthy\""
    if ! kubectl -n argocd get app shopix -o jsonpath='{.status.health.status}' 2>/dev/null | grep -q Healthy; then
      note "détail par ressource — c'est là qu'on voit laquelle bloque :"
      kubectl -n argocd get app shopix \
        -o jsonpath='{range .status.resources[*]}{.kind}/{.name}  →  {.health.status}{"  "}{.health.message}{"\n"}{end}' \
        2>/dev/null | grep -v '  →  Healthy' | sed 's/^/     /'
    fi
    tester "selfHeal est actif (sinon la démo 10 ne montre rien)" \
      "kubectl -n argocd get app shopix -o jsonpath='{.spec.syncPolicy.automated.selfHeal}' | grep -q true"
    tester "le dépôt suivi n'est plus l'URL d'exemple" \
      "! kubectl -n argocd get app shopix -o jsonpath='{.spec.source.repoURL}' | grep -q CHANGEZ-MOI"
  else
    ignorer "application shopix (./setup/05b-depot-gitops.sh)"
  fi
fi

# ══════════════════════════════════════════════ 3. les accès depuis le Mac
etape 3 "Accès navigateur (tunnels)"
if curl -sf -m 3 http://localhost:3000/login -o /dev/null 2>/dev/null; then
  ok "Grafana répond sur http://localhost:3000"
else
  ignorer "tunnel Grafana (./setup/08-acces-j3.sh)"
fi
if curl -sf -m 3 http://localhost:8080/ -o /dev/null 2>/dev/null; then
  ok "ArgoCD répond sur http://localhost:8080"
else
  ignorer "tunnel ArgoCD (./setup/08-acces-j3.sh)"
fi

# ══════════════════════════════════════════════ verdict
echo
titre "Verdict"
printf "%b\n" "$RESUME"
echo
TOTAL=$((REUSSIS + ECHOUES))
if [ "$ECHOUES" -eq 0 ]; then
  printf "%s  %s/%s vérifications passées" "$C_OK" "$REUSSIS" "$TOTAL"
  [ "$IGNORES" -gt 0 ] && printf " (%s ignorée(s))" "$IGNORES"
  printf " — les démonstrations du J3 sont prêtes.%s\n\n" "$C_RAZ"
  exit 0
else
  printf "%s  %s échec(s) sur %s vérifications.%s\n" "$C_KO" "$ECHOUES" "$TOTAL" "$C_RAZ"
  printf "%s  Reportez-vous au tableau « Quand ça casse » du runbook (section 5).%s\n\n" "$C_GRIS" "$C_RAZ"
  exit 1
fi
