#!/usr/bin/env bash
# ArgoCD pour la démonstration GitOps du J3.
#
# ⚠️ À installer APRÈS le J2, jamais avant : avec selfHeal activé, ArgoCD annule
# le « scale à 10 » de la démo 4 et la bascule PSA de la démo 8 pendant qu'elles
# se déroulent. La veille du J3, donc.
cd "$(dirname "$0")/.." || exit 1
source lib/demo.sh
VITESSE=0
SANS_PAUSE="${SANS_PAUSE-1}"
# Sur un cluster distant, les attentes sont plus longues qu'en local.
ATTENTE_MAX="${ATTENTE_MAX-240}"
PROFIL="${PROFIL-ccs}"

titre "ArgoCD — le contrôleur GitOps"
exiger kubectl
annoncer_cluster

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# --server-side est OBLIGATOIRE ici, ce n'est pas une préférence de style.
# Un « kubectl apply » classique écrit tout le manifeste dans l'annotation
# kubectl.kubernetes.io/last-applied-configuration, et la CRD applicationsets
# dépasse à elle seule la limite de 262 144 octets d'une annotation :
#   The CustomResourceDefinition "applicationsets.argoproj.io" is invalid:
#   metadata.annotations: Too long: may not be more than 262144 bytes
# L'apply côté serveur ne pose pas cette annotation — la limite disparaît.
# --force-conflicts reprend la main si un apply classique a déjà partiellement
# installé ArgoCD (c'est le cas après l'erreur ci-dessus).
ARGOCD_MANIFESTE="${ARGOCD_MANIFESTE-https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml}"
if ! kubectl apply -n argocd --server-side --force-conflicts \
      -f "$ARGOCD_MANIFESTE" >/tmp/ccs-argocd.log 2>&1; then
  echo
  sed 's/^/     /' /tmp/ccs-argocd.log | head -8
  echo
  ko "installation d'ArgoCD impossible."
  note "Si l'erreur parle du réseau : le manifeste est tiré de raw.githubusercontent.com."
  note "Si elle parle d'annotation trop longue : votre kubectl ignore --server-side,"
  note "mettez-le à jour (1.22 minimum)."
  exit 1
fi
# « Warning: unrecognized format "int64" » est normal et sans conséquence :
# kubectl ne connaît pas ce format OpenAPI, il le signale et continue.
ok "manifestes appliqués (apply côté serveur)"

# Les CRD viennent d'être créées : on attend qu'elles soient établies avant de
# parler d'Application, sinon l'étape 05b échouerait sur un type inconnu.
attendre_que "les types ArgoCD sont enregistrés" \
  "kubectl get crd applications.argoproj.io -o jsonpath='{.status.conditions[?(@.type==\"Established\")].status}' | grep -q True"

attendre_que "le serveur ArgoCD est prêt" \
  "kubectl -n argocd get deploy argocd-server -o jsonpath='{.status.readyReplicas}' | grep -q 1"

# Mode « insecure » : ArgoCD sert sinon en HTTPS avec un certificat auto-signé, et
# le navigateur affiche un écran d'avertissement rouge devant la salle. En HTTP
# derrière un tunnel local, l'accès est immédiat et sans mise en garde.
kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge \
  -p '{"data":{"server.insecure":"true"}}' >/dev/null
kubectl -n argocd rollout restart deploy argocd-server >/dev/null
attendre_que "le serveur redémarre en HTTP" \
  "kubectl -n argocd rollout status deploy argocd-server --timeout=90s"

# Santé de l'Ingress : ArgoCD considère par défaut qu'un Ingress n'est « Healthy »
# que lorsque status.loadBalancer.ingress est renseigné — c'est-à-dire quand un
# contrôleur lui a attribué une IP publique. Sur Minikube, Traefik est exposé en
# NodePort : ce champ reste vide pour toujours, l'Ingress reste « Progressing », et
# l'application entière reste « Progressing » alors que tout fonctionne. On dit donc
# à ArgoCD qu'ici, un Ingress sans IP est normal.
kubectl -n argocd patch configmap argocd-cm --type merge -p '{"data":{"resource.customizations.health.networking.k8s.io_Ingress":"hs = {}\nhs.status = \"Healthy\"\nhs.message = \"Ingress local (Traefik en NodePort) : aucune IP publique a attendre\"\nreturn hs\n"}}' >/dev/null
# Le contrôleur relit argocd-cm à chaud, mais on force pour ne pas dépendre du délai.
silence "kubectl -n argocd rollout restart statefulset argocd-application-controller"
silence "kubectl -n argocd rollout restart deploy argocd-application-controller"
attendre_que "le contrôleur applique la règle de santé" \
  "kubectl -n argocd get cm argocd-cm -o jsonpath='{.data}' | grep -q networking.k8s.io_Ingress"

# NodePort : utile sur Linux, inopérant sur macOS avec le driver Docker (l'IP du
# nœud vit dans la VM). On le pose quand même, l'accès passe par le tunnel.
kubectl -n argocd patch svc argocd-server -p \
  '{"spec":{"type":"NodePort","ports":[{"port":80,"targetPort":8080,"nodePort":30800,"name":"http"}]}}' >/dev/null

# base64decode par kubectl : « base64 -d » n'existe pas partout (BSD ≠ GNU).
MDP=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o go-template='{{.data.password | base64decode}}' 2>/dev/null)

echo
ok "ArgoCD installé."
note "Accès : ./setup/08-acces-j3.sh puis http://localhost:8080"
note "   identifiant : admin"
note "   mot de passe : ${MDP:-(secret argocd-initial-admin-secret introuvable)}"
echo
note "Dernière étape, une seule fois — déclarer le dépôt Git :"
echo "     ./setup/05b-depot-gitops.sh"
echo
note "Vérification : ./setup/06b-autotest-j3.sh"
