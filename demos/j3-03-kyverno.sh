#!/usr/bin/env bash
# J3 · Module 8 · ~10 min · « Vos règles, en YAML » — la politique comme code avec Kyverno
# Le PSA de la démo 8 applique des niveaux standard. Ici, l'équipe écrit ses propres
# règles, les applique à l'admission, puis les passe en mode progressif (Warn, Audit).
#
#   ./demos/j3-03-kyverno.sh               la démonstration (installe Kyverno s'il manque)
#   ./demos/j3-03-kyverno.sh --preparer    installe seulement Kyverno (~2 min, à faire à la pause)
#   ./demos/j3-03-kyverno.sh --desinstaller retire Kyverno du cluster
cd "$(dirname "$0")/.." || exit 1
source lib/demo.sh
exiger kubectl helm
NS="${NS-shopix}"
ATTENTE_MAX="${ATTENTE_MAX-300}"
POLITIQUE="validatingpolicies.policies.kyverno.io/shopix-bonnes-pratiques"

installer_kyverno() {
  if kubectl -n kyverno get deploy kyverno-admission-controller >/dev/null 2>&1; then
    ok "Kyverno est déjà installé"
  else
    note "installation de Kyverno (chart Helm officiel, ~2 min)"
    helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null 2>&1
    helm repo update kyverno >/dev/null 2>&1
    helm upgrade --install kyverno kyverno/kyverno -n kyverno --create-namespace --wait --timeout 6m >/dev/null \
      || { ko "installation de Kyverno impossible (réseau ? mémoire du cluster ?)"; exit 1; }
    ok "Kyverno installé"
  fi
  # La démo s'appuie sur ValidatingPolicy en v1 (Kyverno ≥ 1.19) : on le vérifie avant la salle.
  if ! kubectl get crd validatingpolicies.policies.kyverno.io -o jsonpath='{.spec.versions[?(@.served==true)].name}' 2>/dev/null | grep -qw v1; then
    ko "ce Kyverno ne sert pas encore l'API policies.kyverno.io/v1 (il faut Kyverno 1.19 ou plus)"
    note "mettre à jour : helm repo update && helm upgrade kyverno kyverno/kyverno -n kyverno"
    exit 1
  fi
}

case "${1-}" in
  --preparer)     titre "Préparation : Kyverno"; annoncer_cluster; installer_kyverno; exit 0 ;;
  --desinstaller) titre "Retrait de Kyverno"
                  kubectl delete "$POLITIQUE" --ignore-not-found >/dev/null 2>&1
                  helm uninstall kyverno -n kyverno && kubectl delete ns kyverno --ignore-not-found
                  ok "Kyverno retiré"; exit 0 ;;
esac

# Filet de sécurité : la politique ne doit pas survivre à la démonstration — sinon elle
# refuserait, plus tard, un Pod de démonstration sans limite mémoire (le glouton, les outils…).
nettoyer() {
  kubectl delete "$POLITIQUE" --ignore-not-found >/dev/null 2>&1
  kubectl -n "$NS" delete pod essai --ignore-not-found --now >/dev/null 2>&1
  kubectl -n "$NS" delete deploy essai --ignore-not-found >/dev/null 2>&1
}
trap nettoyer EXIT

annoncer_cluster
titre "Vos règles, en YAML : la politique comme code (Module 8)"
installer_kyverno
nettoyer    # table rase : une politique ou un Pod « essai » d'une répétition précédente

# ------------------------------------------------------------ 1. ce qui passe aujourd'hui
etape 1 "Ce que le vigile du J2 laisse passer"
dire "Le PSA filtre ce qu'un Pod a le droit d'être : root, privilèges. Il ne dit rien des bonnes pratiques."
pari "Un nginx sans version, sans limite mémoire. Le namespace est en baseline. Passe-t-il ?"
run "kubectl -n $NS run essai --image=nginx"
run "kubectl -n $NS get pod essai -o jsonpath='image={.spec.containers[0].image} · limites={.spec.containers[0].resources}'; echo"
ko "Il passe : aucune version (donc :latest, qui change sous nos pieds), aucune limite (il peut affamer le nœud)."
silence "kubectl -n $NS delete pod essai --now"

# ------------------------------------------------------------ 2. la règle
etape 2 "On écrit la règle"
run "cat k8s/demos/13-kyverno-politique.yaml"
dire "Deux règles en CEL, le langage d'expressions de Kubernetes. Limitées au namespace shopix. Mode : Deny."
run "kubectl apply -f k8s/demos/13-kyverno-politique.yaml"
# Prête = un essai « à blanc » (dry-run côté serveur, qui passe par les webhooks) est refusé.
attendre_que "la politique est active à l'admission" \
  "! kubectl -n $NS run sonde --image=nginx --dry-run=server"

# ------------------------------------------------------------ 3. le refus
etape 3 "Le même nginx, maintenant"
pari "Même commande qu'il y a une minute. Que va répondre l'api-server ?"
run "kubectl -n $NS run essai --image=nginx"
ok "Refusé à l'admission, avec le message écrit par l'équipe — pas un code d'erreur obscur."
pari "Et si je contourne en passant par un Deployment ?"
run "kubectl -n $NS create deployment essai --image=nginx:1.27-alpine"
ok "Refusé aussi : la règle a été générée pour les Deployments (autogen). Version précise, mais pas de limite mémoire."
dire "Sans autogen, le Deployment serait accepté… et ses Pods refusés en silence par le ReplicaSet. Le pire des deux mondes."

# ------------------------------------------------------------ 4. ce qui est conforme passe
etape 4 "Ce qui respecte la règle passe"
dire "On soumet le Deployment du front tel qu'il tourne, à blanc : l'api-server le fait passer par toute la chaîne d'admission, sans rien modifier."
run "kubectl -n $NS get deploy shopix-front -o yaml | kubectl apply --dry-run=server -f -"
ok "Shopix passe : version précise, limites déclarées. La règle ne gêne que ce qui devait l'être."
note "--dry-run=server : l'outil à connaître pour tester une politique sans rien casser (et sans réveiller ArgoCD)."

# ------------------------------------------------------------ 5. le mode progressif
etape 5 "En production, on ne commence jamais par Deny"
dire "Une règle qui refuse du jour au lendemain casse des déploiements. On la passe d'abord en Warn, puis en Audit."
run "kubectl patch $POLITIQUE --type merge -p '{\"spec\":{\"validationActions\":[\"Warn\",\"Audit\"]}}'"
sleep 3
pari "Même nginx, en mode Warn. Refusé, accepté, ou autre chose ?"
run "kubectl -n $NS run essai --image=nginx"
ok "Accepté, mais avec un avertissement : l'équipe est prévenue, rien n'est cassé."
note "Le rapport de conformité se remplit en arrière-plan (une trentaine de secondes)."
sleep 20
run "kubectl -n $NS get policyreport 2>/dev/null || kubectl -n $NS get reports.openreports.io 2>/dev/null"
dire "Le rapport liste les ressources non conformes : c'est le tableau de bord de la dette, avant de passer en Deny."

echo
titre "Ce qu'on retient"
dire "Le PSA applique des niveaux standard ; Kyverno applique VOS règles, écrites en YAML."
dire "Elles se versionnent dans Git, se relisent en revue de code et se déploient par GitOps, comme le reste."
dire "Et on les introduit en douceur : Warn et Audit d'abord, Deny ensuite."
note "Remise en état : automatique (politique et Pods d'essai supprimés). Kyverno reste installé : ./demos/j3-03-kyverno.sh --desinstaller"
