#!/usr/bin/env bash
# Rejoue TOUTES les démonstrations sans pause et vérifie que chacune produit
# bien l'effet attendu. À lancer après le déploiement, et à refaire la veille
# de chaque session. Compter 6 à 8 minutes.
#
#   ./setup/06-autotest.sh            tout
#   ./setup/06-autotest.sh --rapide   saute les scénarios lents (OOMKill, Job)
cd "$(dirname "$0")/.." || exit 1
source lib/demo.sh
VITESSE=0
SANS_PAUSE=1
NS="${NS-shopix}"
PROFIL="${PROFIL-ccs}"
RAPIDE=0
[ "${1-}" = "--rapide" ] && RAPIDE=1

REUSSIS=0; ECHOUES=0; IGNORES=0
RESUME=""

# tester "ce qu'on vérifie" "commande qui doit réussir"
tester() {
  local libelle="$1"; shift
  printf "  %-58s" "$libelle"
  # Sous-shell sans pipefail : on juge sur ce que grep a trouvé, pas sur le code
  # de retour de l'outil en amont (can-i répond « no » en sortant en 1).
  ( set +o pipefail; eval "$@" ) >/tmp/ccs-autotest.log 2>&1
  local code=$?
  if [ $code -eq 0 ]; then
    printf "%s✔ ok%s\n" "$C_OK" "$C_RAZ"
    REUSSIS=$((REUSSIS + 1)); RESUME="$RESUME\n  ✔  $libelle"
  else
    printf "%s✘ ÉCHEC%s\n" "$C_KO" "$C_RAZ"
    ECHOUES=$((ECHOUES + 1)); RESUME="$RESUME\n  ✘  $libelle"
    if [ -s /tmp/ccs-autotest.log ]; then
      sed 's/^/        /' /tmp/ccs-autotest.log | head -4
    else
      printf "        (aucune sortie · code de retour %s)\n" "$code"
    fi
  fi
}

ignorer() {
  printf "  %-58s%s— ignoré%s\n" "$1" "$C_GRIS" "$C_RAZ"
  IGNORES=$((IGNORES + 1)); RESUME="$RESUME\n  —  $1 (ignoré)"
}

# attend qu'une condition devienne vraie, avec un plafond en secondes
patienter() {
  local max="$1"; shift
  local n=0
  while [ $n -lt "$max" ]; do
    ( set +o pipefail; eval "$@" ) >/dev/null 2>&1 && return 0
    sleep 2; n=$((n + 2))
  done
  return 1
}

# raccourci : exécuter un wget depuis le Pod « tools »
depuis_tools() { kubectl -n "$NS" exec tools -- wget -q -T "${2-5}" -O- "$1" 2>/dev/null; }

titre "Autotest des démonstrations CCS"
exiger kubectl minikube

# ══════════════════════════════════════════════ 1. le socle
etape 1 "Le cluster et l'application"

tester "le contexte kubectl répond" \
  "kubectl cluster-info"
tester "deux nœuds sont Ready" \
  "[ \$(kubectl get nodes --no-headers | grep -c ' Ready ') -ge 2 ]"
tester "Calico est actif (sinon les Network Policies sont décoratives)" \
  "kubectl -n kube-system get pods -l k8s-app=calico-node --no-headers | grep -q Running"
tester "le nœud de stockage est étiqueté" \
  "kubectl get nodes -l stockage=oui --no-headers | grep -q ."
tester "le nœud de paiement est étiqueté" \
  "kubectl get nodes -l zone=paiement --no-headers | grep -q ."
tester "les trois déploiements sont prêts" \
  "[ \"\$(kubectl -n $NS get deploy shopix-front -o jsonpath='{.status.readyReplicas}')\" = 2 ] &&
   [ \"\$(kubectl -n $NS get deploy shopix-api -o jsonpath='{.status.readyReplicas}')\" = 2 ] &&
   [ \"\$(kubectl -n $NS get deploy shopix-commandes -o jsonpath='{.status.readyReplicas}')\" = 1 ]"

ARCH_NOEUD=$(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.architecture}')
ARCH_IMAGE=$(docker image inspect shopix:1.0.0 --format '{{.Architecture}}' 2>/dev/null || echo "?")
tester "l'image correspond à l'architecture des nœuds ($ARCH_NOEUD)" \
  "[ \"$ARCH_IMAGE\" = \"?\" ] || [ \"$ARCH_IMAGE\" = \"$ARCH_NOEUD\" ]"

silence "kubectl -n $NS apply -f k8s/demos/tools.yaml"
tester "le Pod « boîte à outils » démarre" \
  "patienter 60 \"kubectl -n $NS get pod tools -o jsonpath='{.status.phase}' | grep -q Running\""

# ══════════════════════════════════════════════ 2. l'application répond
etape 2 "Ce que la salle va voir à l'écran"

tester "la boutique renvoie le catalogue" \
  "depuis_tools http://shopix-front:8080/ | grep -q 'Casque audio Cabestan'"
tester "la page affiche le Pod qui a répondu (Downward API)" \
  "depuis_tools http://shopix-front:8080/ | grep -q 'shopix-front-'"
tester "la page affiche le nœud" \
  "depuis_tools http://shopix-front:8080/ | grep -qi 'nœud\\|noeud'"
tester "le message vient bien de la ConfigMap" \
  "depuis_tools http://shopix-front:8080/ | grep -q 'tient la charge'"
tester "l'API sert le catalogue en JSON" \
  "depuis_tools http://shopix-api:8080/api/produits | grep -q 'SHX-001'"
tester "la clé de paiement vient du Secret" \
  "depuis_tools http://shopix-api:8080/api/paiement 15 | grep -q 'sk_tes'"
tester "les métriques exposent l'histogramme de latence" \
  "depuis_tools http://shopix-api:8080/metrics | grep -q 'shopix_request_duration_seconds_bucket'"
tester "deux Pods différents répondent (répartition de charge)" \
  "[ \$(for i in 1 2 3 4 5 6 7 8; do depuis_tools http://shopix-api:8080/whoami | grep -o 'shopix-api-[a-z0-9-]*'; done | sort -u | wc -l) -ge 2 ]"

# ══════════════════════════════════════════════ 3. démo 5 — placement et santé
etape 3 "Démo 5 — OOMKilled, Pending, sondes"

if [ "$RAPIDE" = "1" ]; then
  ignorer "OOMKill du Pod glouton"
else
  silence "kubectl -n $NS delete pod shopix-gourmand --ignore-not-found --now"
  silence "kubectl -n $NS apply -f k8s/demos/01-oomkill.yaml"
  patienter 60 "kubectl -n $NS get pod shopix-gourmand -o jsonpath='{.status.phase}' | grep -q Running"
  silence "kubectl -n $NS exec shopix-gourmand -- wget -q -T 5 -O- 'http://127.0.0.1:8080/leak?mo=400'"
  tester "le Pod glouton est tué pour dépassement mémoire" \
    "patienter 60 \"kubectl -n $NS get pod shopix-gourmand -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}{.status.containerStatuses[0].state.terminated.reason}' | grep -q OOMKilled\""
  silence "kubectl -n $NS delete pod shopix-gourmand --now"
fi

QUAI=$(kubectl get nodes -l zone=paiement -o jsonpath='{.items[0].metadata.name}')
silence "kubectl taint nodes $QUAI paiement=true:NoSchedule --overwrite"
silence "kubectl -n $NS apply -f k8s/demos/02-taint-pending.yaml"
tester "sans toleration, le Pod reste Pending" \
  "patienter 30 \"kubectl -n $NS get pods -l composant=paiement -o jsonpath='{.items[0].status.phase}' | grep -q Pending\""
silence "kubectl -n $NS apply -f k8s/demos/03-taint-toleration.yaml"
tester "avec la toleration, il démarre" \
  "patienter 90 \"kubectl -n $NS get pods -l composant=paiement -o jsonpath='{.items[*].status.phase}' | grep -q Running\""
silence "kubectl -n $NS delete -f k8s/demos/03-taint-toleration.yaml"
silence "kubectl taint nodes $QUAI paiement=true:NoSchedule-"

silence "kubectl -n $NS apply -f k8s/demos/04-antiaffinite.yaml"
tester "l'anti-affinité stricte laisse le 3e réplica en attente" \
  "patienter 40 \"[ \\\$(kubectl -n $NS get pods -l composant=etale --no-headers | grep -c Pending) -ge 1 ]\""
silence "kubectl -n $NS delete -f k8s/demos/04-antiaffinite.yaml"

CIBLE=$(kubectl -n "$NS" get pods -l composant=api -o jsonpath='{.items[0].metadata.name}')
silence "kubectl -n $NS exec $CIBLE -- wget -q -O- 'http://127.0.0.1:8080/admin/casser?cible=ready'"
tester "une sonde readiness cassée retire le Pod du Service" \
  "patienter 30 \"[ \\\$(kubectl -n $NS get endpoints shopix-api -o jsonpath='{.subsets[*].addresses[*].ip}' | wc -w) -eq 1 ]\""
silence "kubectl -n $NS exec $CIBLE -- wget -q -O- http://127.0.0.1:8080/admin/reparer"
tester "réparée, il revient dans le Service" \
  "patienter 30 \"[ \\\$(kubectl -n $NS get endpoints shopix-api -o jsonpath='{.subsets[*].addresses[*].ip}' | wc -w) -eq 2 ]\""

# ══════════════════════════════════════════════ 4. démo 6 — réseau
etape 4 "Démo 6 — le réseau et le Zero-Trust"

# Le nom complet n'apparaît que dans une réponse positive : un message d'erreur
# de busybox contiendrait « shopix-api » tout court et ferait un faux positif.
tester "le DNS interne résout le nom du Service" \
  "kubectl -n $NS exec tools -- nslookup shopix-api 2>/dev/null | grep -q 'shopix-api.shopix.svc'"
silence "kubectl -n $NS apply -f k8s/demos/05-netpol-deny.yaml"
sleep 4
tester "la règle deny-all coupe réellement l'accès à l'API" \
  "! depuis_tools http://shopix-api:8080/api/produits 4 | grep -q SHX-001"
tester "et la boutique affiche « catalogue indisponible »" \
  "patienter 20 \"depuis_tools http://shopix-front:8080/ 8 | grep -q 'Catalogue indisponible'\""
silence "kubectl -n $NS apply -f k8s/demos/06-netpol-allow-front.yaml"
sleep 4
tester "l'autorisation nominative rend le catalogue au front" \
  "patienter 30 \"depuis_tools http://shopix-front:8080/ 8 | grep -q 'Casque audio Cabestan'\""
tester "mais le Pod « tools », lui, reste dehors" \
  "! depuis_tools http://shopix-api:8080/api/produits 4 | grep -q SHX-001"
silence "kubectl -n $NS delete netpol --all"
sleep 3

# ══════════════════════════════════════════════ 5. démo 7 — stockage
etape 5 "Démo 7 — la donnée qui survit"

silence "kubectl -n $NS exec deploy/shopix-commandes -- wget -q -O- --post-data='' 'http://127.0.0.1:8080/api/commandes?ref=SHX-003'"
tester "la commande est bien enregistrée" \
  "kubectl -n $NS exec deploy/shopix-commandes -- wget -q -O- http://127.0.0.1:8080/api/commandes | grep -q SHX-003"
POD_DONNEES=$(kubectl -n "$NS" get pods -l composant=commandes -o jsonpath='{.items[0].metadata.name}')
silence "kubectl -n $NS delete pod $POD_DONNEES --now"
patienter 90 "kubectl -n $NS get deploy shopix-commandes -o jsonpath='{.status.readyReplicas}' | grep -q 1"
tester "elle survit à la destruction du Pod" \
  "patienter 60 \"kubectl -n $NS exec deploy/shopix-commandes -- wget -q -O- http://127.0.0.1:8080/api/commandes | grep -q SHX-003\""
tester "alors que l'API sans volume, elle, ne retient rien" \
  "! kubectl -n $NS exec deploy/shopix-api -- wget -q -O- http://127.0.0.1:8080/api/commandes | grep -q SHX-003"

if [ "$RAPIDE" = "1" ]; then
  ignorer "Job de facturation"
else
  silence "kubectl -n $NS delete job facturation --ignore-not-found"
  silence "kubectl -n $NS apply -f k8s/demos/07-job-facturation.yaml"
  tester "le Job de facturation se termine en Completed" \
    "patienter 120 \"kubectl -n $NS get job facturation -o jsonpath='{.status.succeeded}' | grep -q 1\""
  silence "kubectl -n $NS delete job facturation --ignore-not-found"
fi

# ══════════════════════════════════════════════ 6. démo 8 — sécurité
etape 6 "Démo 8 — les trois refus"

silence "kubectl apply -f k8s/demos/08-rbac-viewer.yaml"
tester "le compte de service peut lister les Pods" \
  "kubectl -n $NS auth can-i list pods --as=system:serviceaccount:$NS:stagiaire | grep -q yes"
# « auth can-i » répond « no » sur la sortie standard ET sort en code 1 :
# c'est bien le texte qu'on teste ici, pas le code de retour.
tester "mais ne peut pas en créer" \
  "kubectl -n $NS auth can-i create pods --as=system:serviceaccount:$NS:stagiaire | grep -q no"
tester "ni lire les secrets" \
  "kubectl -n $NS auth can-i get secrets --as=system:serviceaccount:$NS:stagiaire | grep -q no"

silence "kubectl label ns $NS pod-security.kubernetes.io/enforce=restricted --overwrite"
silence "kubectl -n $NS delete pod nginx-officiel --ignore-not-found --now"
tester "en mode restricted, le nginx officiel est refusé à l'admission" \
  "! kubectl -n $NS apply -f k8s/demos/09-pod-root.yaml"
tester "alors que Shopix, elle, passe" \
  "kubectl -n $NS rollout restart deploy shopix-front && kubectl -n $NS rollout status deploy shopix-front --timeout=120s"
silence "kubectl label ns $NS pod-security.kubernetes.io/enforce=baseline --overwrite"

tester "le Secret se décode sans le moindre mot de passe" \
  "kubectl -n $NS get secret shopix-paiement -o go-template='{{.data.PAIEMENT_CLE | base64decode}}' | grep -q sk_test"

# ══════════════════════════════════════════════ 7. l'accès extérieur
etape 7 "L'accès depuis le navigateur"

if kubectl -n traefik get deploy traefik >/dev/null 2>&1; then
  tester "Traefik est prêt" \
    "kubectl -n traefik get deploy traefik -o jsonpath='{.status.readyReplicas}' | grep -q 1"

  # On teste le routage de l'Ingress DEPUIS le cluster : c'est la seule chose qui
  # dépend de nos manifestes. La joignabilité depuis le Mac est un autre sujet.
  tester "l'Ingress route bien la racine vers le front" \
    "kubectl -n $NS exec tools -- wget -q -T 8 -O- --header='Host: shopix.local' http://traefik.traefik:80/ | grep -q 'Casque audio Cabestan'"
  tester "et /api vers l'API" \
    "kubectl -n $NS exec tools -- wget -q -T 8 -O- --header='Host: shopix.local' http://traefik.traefik:80/api/produits | grep -q 'SHX-001'"

  # Accès depuis le poste : dépend du système et du tunnel, ce n'est pas bloquant.
  PORT_ACCES="${PORT_ACCES-8888}"
  if curl -s -m 5 "http://shopix.local:$PORT_ACCES/" 2>/dev/null | grep -q 'Casque audio Cabestan'; then
    ok "accès depuis le navigateur : http://shopix.local:$PORT_ACCES"
  elif [ "$(uname -s)" = "Darwin" ]; then
    note "pas d'accès depuis le Mac pour l'instant — c'est normal sans tunnel :"
    note "lancez ./setup/07-acces.sh dans un terminal dédié (l'IP du nœud n'est pas routable sur macOS)"
  else
    IP=$(minikube -p "$PROFIL" ip 2>/dev/null)
    if curl -s -m 5 -H 'Host: shopix.local' "http://$IP:30080/" 2>/dev/null | grep -q 'Casque'; then
      ok "accès depuis le poste : http://shopix.local:30080"
    else
      note "pas d'accès direct — vérifiez /etc/hosts"
    fi
  fi
else
  ignorer "Traefik / Ingress (non installé)"
fi

# ══════════════════════════════════════════════ ménage et verdict
etape 8 "Remise en état"
silence "./demos/reset.sh --j2"
silence "kubectl -n $NS exec deploy/shopix-commandes -- rm -f /data/commandes.json"
silence "kubectl -n $NS rollout restart deploy shopix-commandes"
ok "environnement remis dans l'état de départ"

echo
titre "Verdict"
printf "%b\n" "$RESUME"
echo
TOTAL=$((REUSSIS + ECHOUES))
if [ "$ECHOUES" -eq 0 ]; then
  printf "%s  %s/%s vérifications passées" "$C_OK" "$REUSSIS" "$TOTAL"
  [ "$IGNORES" -gt 0 ] && printf " (%s ignorée(s))" "$IGNORES"
  printf " — les démonstrations sont prêtes.%s\n\n" "$C_RAZ"
  exit 0
else
  printf "%s  %s échec(s) sur %s vérifications.%s\n" "$C_KO" "$ECHOUES" "$TOTAL" "$C_RAZ"
  printf "%s  Reportez-vous au tableau « Quand ça casse » du runbook (section 5).%s\n\n" "$C_GRIS" "$C_RAZ"
  exit 1
fi
