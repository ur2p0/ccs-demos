#!/usr/bin/env bash
# Pile d'observabilité pour les démonstrations du J3 (Prometheus, Grafana, Loki).
# À lancer la veille du J3 : le téléchargement des images prend plusieurs minutes.
#
# Ce script ne laisse RIEN à faire à la main : le tableau de bord et la source de
# données Loki sont provisionnés automatiquement. Vérifiez le résultat avec
# ./setup/06b-autotest-j3.sh avant de refermer le Mac.
cd "$(dirname "$0")/.." || exit 1
source lib/demo.sh
VITESSE=0
SANS_PAUSE="${SANS_PAUSE-1}"
# Sur un cluster distant, les attentes sont plus longues qu'en local.
ATTENTE_MAX="${ATTENTE_MAX-240}"
PROFIL="${PROFIL-ccs}"
MDP_GRAFANA="${MDP_GRAFANA-shopix}"

titre "Observabilité — Prometheus, Grafana, Loki"
exiger helm kubectl
annoncer_cluster
note "compter ~2 Go de RAM supplémentaires dans le cluster"
note "sur un Mac, c'est ce qui met Minikube à genoux : préférez Kapsule (terraform/)"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1
helm repo update >/dev/null 2>&1

# Le namespace d'abord : loki-stack s'installe désormais en premier.
# « get || create » plutôt que « apply » : le namespace a pu être créé par helm
# (--create-namespace), et apply râlerait sur une annotation manquante.
kubectl get namespace observabilite >/dev/null 2>&1 || kubectl create namespace observabilite >/dev/null

# ORDRE VOLONTAIRE : loki-stack AVANT kube-prometheus-stack. Le « --wait » de ce
# dernier attend que Grafana soit prêt ; si une ConfigMap fautive de loki-stack
# traîne encore, Grafana ne démarrera jamais et helm attendra jusqu'au timeout
# (« Progress deadline exceeded »). En réglant Loki d'abord, la cause est retirée
# avant qu'on attende le symptôme.
# Loki et promtail pèsent ~500 Mo et trois Pods de plus. Sur un cluster juste en
# mémoire, s'en passer coûte seulement le panneau « Journaux » de la démo 9 — que le
# script de démonstration rattrape avec un « kubectl logs ».
LOKI_OK=oui
if [ "${LOKI-oui}" = "non" ]; then
  LOKI_OK=non
  note "Loki volontairement écarté (LOKI=non) — le panneau « Journaux » restera vide"
  silence "helm uninstall loki --namespace observabilite"
  silence "kubectl -n observabilite delete cm datasource-loki --ignore-not-found"
fi
# ⚠️ grafana.enabled=false NE SUFFIT PAS. Le chart loki-stack crée une ConfigMap de
# source de données (étiquetée grafana_datasource) dès que
# grafana.sidecar.datasources.enabled est vrai — sa valeur par défaut — et il y
# déclare Loki avec isDefault: true. Le Grafana de kube-prometheus-stack la ramasse,
# se retrouve avec DEUX sources par défaut (Loki et Prometheus), et refuse de
# démarrer :
#   Datasource provisioning error: datasource.yaml config is invalid.
#   Only one datasource per organization can be marked as default
# Le piège est sournois : le Grafana déjà lancé continue de tourner, c'est le
# prochain redémarrage qui échoue. On coupe donc cette ConfigMap à la source, et on
# garde la nôtre (datasource-loki.yaml), qui fixe l'uid et pose isDefault: false.
[ "$LOKI_OK" = "oui" ] && helm upgrade --install loki grafana/loki-stack \
  --namespace observabilite \
  --set loki.persistence.enabled=false \
  --set grafana.enabled=false \
  --set grafana.sidecar.datasources.enabled=false \
  --set loki.isDefault=false \
  --set promtail.enabled=true \
  --wait --timeout 8m >/dev/null 2>&1 \
  || { LOKI_OK=non; note "Loki non installé — seul le panneau « Journaux » sera vide"; }

# Défensif : si une installation antérieure a laissé la ConfigMap fautive de
# loki-stack, on la retire explicitement (helm le fait normalement lui-même).
silence "kubectl -n observabilite delete cm loki-loki-stack --ignore-not-found"

# Réparation d'un Grafana déjà bloqué : si une installation précédente l'a laissé en
# CrashLoopBackOff, l'étape suivante (helm --wait) attendrait indéfiniment un Pod qui
# ne peut pas démarrer. La cause vient d'être retirée : on relance Grafana tout de suite.
DEP_GRAF=$(kubectl -n observabilite get deploy -l app.kubernetes.io/name=grafana \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$DEP_GRAF" ] && ! kubectl -n observabilite rollout status "deploy/$DEP_GRAF" --timeout=5s >/dev/null 2>&1; then
  note "Grafana est bloqué par une installation précédente — relance maintenant que la cause est retirée"
  kubectl -n observabilite rollout restart "deploy/$DEP_GRAF" >/dev/null
fi


# sidecar.datasources.uid : on FIGE l'uid de la source Prometheus, parce que le
# tableau de bord la référence par uid et non par nom. Sans ça, l'uid est généré
# et tous les panneaux affichent « Datasource not found ».
helm upgrade --install obs prometheus-community/kube-prometheus-stack \
  --namespace observabilite --create-namespace \
  --set grafana.adminPassword="$MDP_GRAFANA" \
  --set grafana.service.type=NodePort \
  --set grafana.service.nodePort=30300 \
  --set grafana.sidecar.datasources.uid=prometheus \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.retention=2h \
  --set alertmanager.enabled=false \
  --set prometheus.prometheusSpec.resources.requests.memory=512Mi \
  --wait --timeout 12m || {
    ko "installation de kube-prometheus-stack en échec. État du namespace :"
    kubectl -n observabilite get pods | sed 's/^/     /'
    echo
    note "Un Pod Grafana en CrashLoopBackOff ? Ses logs disent pourquoi :"
    echo "     kubectl -n observabilite logs deploy/obs-grafana -c grafana --tail=20"
    exit 1
  }


# ⚠️ Jamais « kubectl apply -f k8s/observabilite/ » : le dossier contient aussi le
# JSON du tableau de bord, qui n'est pas un manifeste Kubernetes. L'apply échouait
# silencieusement et le ServiceMonitor n'était jamais posé.
kubectl apply -f k8s/observabilite/servicemonitor.yaml    || ko "ServiceMonitor non appliqué"
if [ "$LOKI_OK" = "oui" ]; then
  kubectl apply -f k8s/observabilite/datasource-loki.yaml || ko "source de données Loki non déclarée"
fi

# Le tableau de bord : le sidecar de Grafana charge toute ConfigMap étiquetée
# grafana_dashboard. Plus d'import manuel dans l'interface.
kubectl -n observabilite create configmap tableau-shopix \
  --from-file=tableau-shopix.json=k8s/observabilite/tableau-shopix.json \
  --dry-run=client -o yaml \
  | kubectl label --local -f - grafana_dashboard=1 -o yaml --dry-run=client \
  | kubectl apply -f - >/dev/null || ko "tableau de bord non provisionné"

# On redémarre Grafana volontairement, pour deux raisons. La première : le
# rechargement à chaud des sources de données n'est pas fiable selon les versions
# du chart. La seconde, plus importante : c'est un TEST DE SURVIE. Une erreur de
# provisioning n'empêche pas un Grafana déjà lancé de tourner — elle empêche le
# suivant de démarrer. Mieux vaut le découvrir ici, la veille, qu'au premier
# redémarrage en séance.
SVC_GRAF=$(kubectl -n observabilite get svc -l app.kubernetes.io/name=grafana \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
DEP_GRAF=$(kubectl -n observabilite get deploy -l app.kubernetes.io/name=grafana \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$DEP_GRAF" ]; then
  kubectl -n observabilite rollout restart "deploy/$DEP_GRAF" >/dev/null
  # Timeout interne court : c'est attendre_que qui compte, pas kubectl.
  if ! attendre_que "Grafana redémarre avec ses sources de données" \
        "kubectl -n observabilite rollout status deploy/$DEP_GRAF --timeout=15s"; then
    # Un redémarrage qui traîne sur un cluster neuf, c'est presque toujours un tirage
    # d'image ou un Pod en attente de ressources. On le montre au lieu de continuer.
    ko "Grafana n'est pas revenu dans le délai. État du namespace :"
    kubectl -n observabilite get pods -o wide | sed 's/^/     /'
    echo
    note "Événements récents (les 8 derniers) :"
    kubectl -n observabilite get events --sort-by=.lastTimestamp 2>/dev/null \
      | tail -8 | sed 's/^/     /'
    echo
    note "La pile est installée : relancez ./setup/06b-autotest-j3.sh dans deux minutes."
    note "Si un Pod reste Pending, les nœuds manquent de RAM — passez à un gabarit plus gros"
    note "(terraform apply -var type_noeud=GP1-XS) ou retirez Loki."
  fi
fi

echo
ok "Pile installée."

note "Accès : ./setup/08-acces-j3.sh dans un terminal dédié,"
note "puis http://localhost:3000 — admin / $MDP_GRAFANA"
note "(le tunnel fonctionne aussi bien sur Minikube que sur Kapsule)"
note "Le tableau « Shopix — observabilité (formation CCS) » est déjà là : pas d'import."
echo
note "Générateur de trafic — sans lui tous les panneaux sont plats :"
echo "     kubectl apply -f k8s/demos/10-charge.yaml"
note "Prometheus garde 2 h d'historique et n'a pas de disque : après un"
note "« minikube stop », les métriques repartent de zéro. Lancez donc le générateur"
note "au moins 30 minutes avant la démonstration, le J3 au matin."
echo
note "Vérification : ./setup/06b-autotest-j3.sh"
