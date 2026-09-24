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
  --wait --timeout 12m || { ko "installation en échec"; exit 1; }

LOKI_OK=oui
helm upgrade --install loki grafana/loki-stack \
  --namespace observabilite \
  --set loki.persistence.enabled=false \
  --set grafana.enabled=false \
  --set promtail.enabled=true \
  --wait --timeout 8m >/dev/null 2>&1 \
  || { LOKI_OK=non; note "Loki non installé — seul le panneau « Journaux » sera vide"; }

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

# Le sidecar « datasources » écrit le fichier de provisioning puis demande à
# Grafana de recharger. Ce rechargement n'est pas instantané et dépend de la
# version du chart : un redémarrage de Grafana supprime toute incertitude, et ne
# coûte que vingt secondes en préparation.
SVC_GRAF=$(kubectl -n observabilite get svc -l app.kubernetes.io/name=grafana \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
DEP_GRAF=$(kubectl -n observabilite get deploy -l app.kubernetes.io/name=grafana \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$DEP_GRAF" ]; then
  kubectl -n observabilite rollout restart "deploy/$DEP_GRAF" >/dev/null
  attendre_que "Grafana redémarre avec ses sources de données" \
    "kubectl -n observabilite rollout status deploy/$DEP_GRAF --timeout=120s"
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
