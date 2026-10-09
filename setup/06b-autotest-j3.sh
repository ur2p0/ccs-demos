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
# Le Pod « tools » est un Pod nu : une éviction sous pression mémoire le fait
# disparaître définitivement. On le recrée donc plutôt que de supposer qu'il est là.
silence "kubectl -n $NS delete pod tools --ignore-not-found --now"
silence "appliquer_demo k8s/demos/tools.yaml"
if ! patienter 90 "kubectl -n $NS get pod tools -o jsonpath='{.status.phase}' | grep -q Running"; then
  ko "le Pod « tools » ne démarre pas — les tests qui passent par lui sont impossibles."
  kubectl -n "$NS" get pod tools -o wide 2>&1 | sed 's/^/     /'
  kubectl -n "$NS" describe pod tools 2>/dev/null | grep -A4 "Events:" | sed 's/^/     /'
  note "Sur un cluster managé, l'image doit venir du registre : vérifiez newName dans"
  note "$(overlay_cluster)/kustomization.yaml, ou exportez IMAGE_SHOPIX."
  exit 1
fi

# ══════════════════════════════════════════════ 1. la pile d'observabilité
etape 1 "Prometheus, Grafana, Loki"

OBS=oui
if ! kubectl get ns observabilite >/dev/null 2>&1; then
  OBS=non
  ignorer "pile d'observabilité (namespace absent — ./setup/04-observabilite.sh)"
fi

if [ "$OBS" = "oui" ]; then
# Un Pod est bon si son STATUS est Running avec tous ses conteneurs prêts, ou
# Completed. Juste après un « rollout restart », l'ancien Pod est encore en
# Terminating : d'où l'attente, plutôt qu'un jugement à la première seconde.
pods_non_prets() {
  kubectl -n observabilite get pods --no-headers 2>/dev/null | awk '
    { split($2, r, "/");
      ok = ((($3 == "Running") && (r[1] == r[2])) || $3 == "Completed");
      if (!ok) print }'
}
attendre_pods_obs() {
  local n=0
  while [ $n -lt 150 ]; do
    [ -z "$(pods_non_prets)" ] && return 0
    sleep 3; n=$((n + 3))
  done
  return 1
}
tester "les Pods d'observabilité sont tous prêts" "attendre_pods_obs"
if [ -n "$(pods_non_prets)" ]; then
  note "Pods qui ne sont pas prêts — c'est la cause à traiter :"
  pods_non_prets | sed 's/^/     /'
  echo
  note "Pourquoi leurs conteneurs se sont arrêtés (OOMKilled = mémoire insuffisante) :"
  for _p in $(pods_non_prets | awk '{print $1}'); do
    kubectl -n observabilite get pod "$_p" -o go-template='{{range .status.containerStatuses}}     {{.name}} · prêt={{.ready}} · redémarrages={{.restartCount}}{{with .lastState.terminated}} · dernier arrêt={{.reason}} (code {{.exitCode}}){{end}}
{{end}}' 2>/dev/null
  done
  echo
  # Le « pourquoi » d'un conteneur qui sort en code 1 n'est pas dans son statut :
  # il est dans les logs de l'instance PRÉCÉDENTE, celle qui vient de mourir.
  note "Ce que disait le conteneur avant de mourir (--previous) :"
  for _p in $(pods_non_prets | awk '{print $1}'); do
    for _c in $(kubectl -n observabilite get pod "$_p" \
                 -o jsonpath='{range .status.containerStatuses[?(@.ready==false)]}{.name} {end}' 2>/dev/null); do
      printf "     ── %s / %s\n" "$_p" "$_c"
      kubectl -n observabilite logs "$_p" -c "$_c" --previous --tail=25 2>&1 \
        | sed 's/^/        /'
    done
  done
  echo
  note "Consommation des nœuds — c'est là qu'on voit si le cluster est trop petit :"
  kubectl top nodes 2>/dev/null | sed 's/^/     /' || note "     (metrics-server pas encore prêt)"
  kubectl get nodes -o custom-columns='NOEUD:.metadata.name,RAM_ALLOUABLE:.status.allocatable.memory,CPU:.status.allocatable.cpu' \
    --no-headers 2>/dev/null | sed 's/^/     /'
  echo
  note "Comment lire ce qui précède :"
  note "  · OOMKilled / code 137 → le cluster est trop petit. Deux remèdes :"
  echo "        cd terraform && terraform apply -var type_noeud=GP1-XS   # 16 Go/nœud, ~4,46 €/jour"
  echo "        LOKI=non ./setup/04-observabilite.sh                      # on se passe de Loki"
  note "  · Error / code 1 avec les nœuds sous 50 % → ce n'est PAS la mémoire."
  note "    La réponse est dans les logs --previous ci-dessus : configuration refusée,"
  note "    fichier de provisioning invalide, dépendance injoignable."
fi

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
DEP_GRAF=$(kubectl -n observabilite get deploy -l app.kubernetes.io/name=grafana \
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
    "patienter 120 \"kubectl -n $NS exec tools -- wget -q -T 5 --header='$AUTH' -O- '$GRAF/api/datasources/uid/loki' | grep -q loki\""
  if ! kubectl -n "$NS" exec tools -- wget -q -T 5 --header="$AUTH" -O- "$GRAF/api/datasources/uid/loki" 2>/dev/null | grep -q loki; then
    note "Toutes les ConfigMaps de sources de données, et leur contenu :"
    kubectl -n observabilite get cm -l grafana_datasource=1 --no-headers -o custom-columns=NOM:.metadata.name 2>/dev/null | sed 's/^/     /'
    note "Combien se déclarent « par défaut » ? Plus d'une, et Grafana refuse de démarrer :"
    kubectl -n observabilite get cm -l grafana_datasource=1 -o yaml 2>/dev/null \
      | grep -iE "^  *name:|isDefault|  *type:|  *uid:" | sed 's/^/     /'
    note "« Only one datasource per organization can be marked as default » dans les logs"
    note "de Grafana = ce doublon. C'est un refus de démarrage, pas un avertissement."
    note "Ce que dit le sidecar qui devrait la charger :"
    kubectl -n observabilite logs "deploy/${DEP_GRAF:-obs-grafana}" -c grafana-sc-datasources --tail=12 2>&1 | sed 's/^/     /'
    note "Sans Loki, seul le panneau « Journaux » de la démo 9 est vide : les cinq autres"
    note "panneaux et tout le déroulé de la démonstration tiennent debout."
  fi
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
