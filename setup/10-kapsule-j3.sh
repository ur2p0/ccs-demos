#!/usr/bin/env bash
# Prépare TOUT le J3 sur le cluster Kapsule, après un « terraform apply ».
#
#   cd terraform && terraform apply && cd ..
#   ./setup/10-kapsule-j3.sh
#
# Le script enchaîne : lecture des sorties Terraform, connexion au registre,
# construction et poussée de l'image amd64, déploiement de Shopix, pile
# d'observabilité, ArgoCD, dépôt GitOps, puis l'autotest.
#
# Pourquoi Kapsule pour le J3 : Prometheus + Grafana + Loki + ArgoCD demandent
# environ 4 Go de RAM au cluster, ce qu'un Minikube sur Mac ne tient pas en plus
# des deux nœuds et de Shopix. Le J1 et le J2 restent en local.
#
# Il ne touche JAMAIS au cluster Minikube : il force KUBECONFIG sur celui de
# Terraform pour toute sa durée.
cd "$(dirname "$0")/.." || exit 1
source lib/demo.sh
VITESSE=0
# Script de préparation, pas de démonstration : il ne doit jamais attendre une touche.
# Exporté pour que 04, 05, 05b et 06b en héritent.
export SANS_PAUSE=1
# Sur un cluster distant, tout est plus lent qu'en local : tirage d'images depuis le
# registre, provisionnement du LoadBalancer, démarrage de la pile d'observabilité.
export ATTENTE_MAX="${ATTENTE_MAX-300}"
NS="${NS-shopix}"
TAG="${TAG-1.0.0}"
# Les nœuds Kapsule sont en x86_64. On ne construit donc que amd64 : la variante
# arm64 ne servirait à rien ici et double le temps d'émulation.
PLATEFORMES="${PLATEFORMES-linux/amd64}"

titre "J3 sur Kapsule — préparation complète"
exiger kubectl docker git

# ------------------------------------------------------------ 1. le kubeconfig
KUBE="$PWD/terraform/kubeconfig.yaml"
if [ ! -f "$KUBE" ]; then
  ko "kubeconfig introuvable : $KUBE"
  note "Créez d'abord le cluster :"
  echo "     cd terraform && terraform init && terraform apply"
  exit 1
fi
export KUBECONFIG="$KUBE"
ok "kubeconfig : terraform/kubeconfig.yaml"

if [ "$(type_cluster)" != "kapsule" ]; then
  ko "ce kubeconfig ne mène pas à un cluster Kapsule."
  annoncer_cluster
  note "Vérifiez « terraform output » et l'état du cluster dans la console Scaleway."
  exit 1
fi
annoncer_cluster
run "kubectl get nodes -o wide"

# ------------------------------------------------------- 2. le registre d'images
REGISTRE=$(terraform -chdir=terraform output -raw registre 2>/dev/null)
if [ -z "$REGISTRE" ]; then
  ko "sortie Terraform « registre » introuvable — relancez terraform apply"
  exit 1
fi
ok "registre : $REGISTRE"

if [ -z "${SCW_SECRET_KEY-}" ]; then
  ko "SCW_SECRET_KEY n'est pas dans l'environnement — nécessaire pour pousser l'image."
  note "     export SCW_SECRET_KEY=…    (la même clé que pour Terraform)"
  exit 1
fi
printf '%s' "$SCW_SECRET_KEY" \
  | docker login "${REGISTRE%%/*}" -u nologin --password-stdin >/dev/null 2>&1 \
  || { ko "connexion au registre refusée — vérifiez SCW_SECRET_KEY"; exit 1; }
ok "connecté à ${REGISTRE%%/*}"

# --------------------------------------------- 3. l'image, et son nom dans l'overlay
note "construction $PLATEFORMES — l'architecture émulée prend 2 à 4 minutes sur un Mac ARM"
REGISTRE="$REGISTRE" TAG="$TAG" PLATEFORMES="$PLATEFORMES" ./setup/02b-images-multiarch.sh \
  || { ko "construction ou poussée de l'image en échec"; exit 1; }

# Les manifestes de k8s/demos/ ne passent pas par kustomize : c'est cette variable
# qui leur donne le bon nom d'image (voir appliquer_demo dans lib/demo.sh).
export IMAGE_SHOPIX="$REGISTRE/shopix:$TAG"

python3 - "$REGISTRE/shopix" <<'PYEOF'
import re, sys, pathlib
nom = sys.argv[1]
p = pathlib.Path('k8s/overlays/scaleway/kustomization.yaml')
s = p.read_text(encoding='utf-8')
s2 = re.sub(r'(\n\s*newName:\s*).*', lambda m: m.group(1) + nom, s, count=1)
p.write_text(s2, encoding='utf-8')
print(f'   ℹ newName inscrit dans l\'overlay scaleway : {nom}')
PYEOF

# ------------------------------------------------------------ 4. Shopix
run "kubectl apply -k k8s/overlays/scaleway"
# Timeout interne court : c'est attendre_que qui compte le temps, pas kubectl.
attendre_que "shopix-api est prêt"       "kubectl -n $NS rollout status deploy/shopix-api --timeout=15s"
attendre_que "shopix-front est prêt"     "kubectl -n $NS rollout status deploy/shopix-front --timeout=15s"
attendre_que "shopix-commandes est prêt" "kubectl -n $NS rollout status deploy/shopix-commandes --timeout=15s"
run "kubectl -n $NS get pods -o wide"

# L'overlay met shopix-front en LoadBalancer : Scaleway attribue une IP publique.
attendre_que "le LoadBalancer reçoit une IP publique" \
  "[ -n \"\$(kubectl -n $NS get svc shopix-front -o jsonpath='{.status.loadBalancer.ingress[0].ip}')\" ]"
IP_PUB=$(kubectl -n "$NS" get svc shopix-front -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
ok "Boutique : http://$IP_PUB:8080    ← à montrer en séance, c'est une vraie IP publique"

# ------------------------------------------------------ 5. les piles du J3
./setup/04-observabilite.sh || { ko "pile d'observabilité en échec"; exit 1; }
./setup/05-argocd.sh        || { ko "ArgoCD en échec"; exit 1; }
CHEMIN=k8s/overlays/scaleway ./setup/05b-depot-gitops.sh \
  || { ko "dépôt GitOps en échec"; exit 1; }

silence "appliquer_demo k8s/demos/10-charge.yaml"
ok "générateur de trafic lancé"

# ------------------------------------------------------------ 6. le verdict
./setup/06b-autotest-j3.sh
CODE=$?

echo
titre "Ce qu'il reste à faire"
note "1. le chemin contient des espaces — gardez les guillemets :"
echo "     export KUBECONFIG=\"$KUBE\""
note "2. ./setup/08-acces-j3.sh      dans un terminal dédié (Grafana 3000, ArgoCD 8080)"
note "3. la boutique publique : http://$IP_PUB:8080"
echo
note "Et à la fin de la session, sans faute :"
echo "     cd terraform && terraform destroy"
note "Deux nœuds DEV1-L ≈ 2,06 €/jour, plus 0,33 €/jour par LoadBalancer."
exit $CODE
