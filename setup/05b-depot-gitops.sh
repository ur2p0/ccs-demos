#!/usr/bin/env bash
# Déclare à ArgoCD le dépôt Git qui contient ce dossier.
#
#   ./setup/05b-depot-gitops.sh                    # dépôt « ccs-demos » de votre compte
#   ./setup/05b-depot-gitops.sh <url-complete>     # pour un autre dépôt
#   DEPOT=autre-nom ./setup/05b-depot-gitops.sh    # pour un autre nom
#
# Sans argument, le propriétaire est lu depuis la CLI GitHub (gh api user).
#
# Ce que fait le script :
#   1. initialise ce dossier comme dépôt Git s'il ne l'est pas déjà ;
#   2. inscrit l'URL dans gitops/apps/shopix.yaml ;
#   3. crée le dépôt sur GitHub s'il n'existe pas (nécessite « gh auth login ») ;
#   4. committe et pousse la branche main ;
#   5. applique l'Application et attend qu'elle passe Synced / Healthy.
#
# VISIBILITE=private ./setup/05b-depot-gitops.sh <url>   pour un dépôt privé
# (il faudra alors déclarer les identifiants à ArgoCD, voir gitops/README.md)
#
# ⚠️ Dépôt PUBLIC : k8s/base/secret.yaml contient une clé de paiement FICTIVE
# (sk_test_shopix_4242_ne_pas_utiliser). C'est volontaire — c'est l'accroche du
# Module 8 : « un Secret dans Git, c'est du base64, pas du chiffrement ». Ne
# poussez jamais ce dépôt avec une vraie valeur à cet endroit.
cd "$(dirname "$0")/.." || exit 1
source lib/demo.sh
VITESSE=0
NS="${NS-shopix}"

DEPOT="${DEPOT-ccs-demos}"
URL="${1-}"

titre "Dépôt GitOps → ArgoCD"
exiger git kubectl

# Sans URL explicite : on déduit le propriétaire du compte GitHub authentifié.
if [ -z "$URL" ]; then
  if ! command -v gh >/dev/null 2>&1; then
    ko "la CLI GitHub n'est pas installée — donnez l'URL complète, ou : brew install gh"
    exit 1
  fi
  PROPRIO=$(gh api user --jq .login 2>/dev/null)
  if [ -z "$PROPRIO" ]; then
    ko "gh n'est pas authentifié — lancez « gh auth login », ou donnez l'URL complète"
    exit 1
  fi
  URL="https://github.com/$PROPRIO/$DEPOT.git"
  ok "compte GitHub détecté : $PROPRIO"
fi
note "dépôt visé : $URL"
case "$URL" in
  *CHANGEZ-MOI*) ko "remplacez l'URL d'exemple par la vôtre"; exit 1 ;;
esac

# ------------------------------------------------------------------ 1. le dépôt
if [ -d .git ]; then
  ok "dépôt Git déjà initialisé"
else
  git init -q
  git symbolic-ref HEAD refs/heads/main      # « main » et non « master »
  ok "dépôt Git initialisé (branche main)"
fi

if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$URL"
  note "dépôt distant mis à jour : $URL"
else
  git remote add origin "$URL"
  note "dépôt distant déclaré : $URL"
fi

# ------------------------------------------------------- 2. l'URL dans le manifeste
python3 - "$URL" <<'PYEOF'
import re, sys, pathlib
url = sys.argv[1]
p = pathlib.Path('gitops/apps/shopix.yaml')
s = p.read_text(encoding='utf-8')
s2 = re.sub(r'(\n\s*repoURL:\s*).*', lambda m: m.group(1) + url, s, count=1)
s2 = s2.replace('# ⚠️ Renseignez repoURL avec l\'adresse de VOTRE dépôt avant d\'appliquer ce fichier.\n',
                '# repoURL est renseigné par ./setup/05b-depot-gitops.sh.\n')
p.write_text(s2, encoding='utf-8')
print('   ℹ repoURL inscrit dans gitops/apps/shopix.yaml')
PYEOF

# ------------------------------------------- 3. le dépôt distant, s'il n'existe pas
# Avec la CLI GitHub authentifiée (« gh auth login »), on crée le dépôt sans
# passer par l'interface web. Sinon on se contente de vérifier qu'il existe.
VISIBILITE="${VISIBILITE-public}"
if ! git ls-remote "$URL" >/dev/null 2>&1; then
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    NOM=$(printf '%s' "$URL" | sed -E 's#.*github\.com[:/]##; s#\.git$##')
    note "dépôt distant absent — création via gh : $NOM ($VISIBILITE)"
    gh repo create "$NOM" "--$VISIBILITE" --description "Démonstrations de la formation CCS" \
      || { ko "création du dépôt impossible — créez-le à la main sur GitHub"; exit 1; }
    ok "dépôt créé sur GitHub"
  else
    ko "le dépôt distant est injoignable : $URL"
    note "Créez-le vide sur GitHub (sans README ni .gitignore), ou installez la CLI :"
    echo "     brew install gh && gh auth login"
    exit 1
  fi
fi

# ------------------------------------------------------------------ 4. le push
# Sans identité configurée, « git commit » échoue — et un échec silencieux ici
# laisserait ArgoCD pointer sur un dépôt vide.
if [ -z "$(git config user.name)" ] || [ -z "$(git config user.email)" ]; then
  ko "git n'a pas d'identité configurée. Une fois pour toutes :"
  echo "     git config --global user.name \"Votre Nom\""
  echo "     git config --global user.email \"vous@exemple.fr\""
  exit 1
fi

git add -A
if git diff --cached --quiet 2>/dev/null; then
  note "rien de nouveau à committer"
else
  git commit -q -m "Démonstrations CCS — état déclaré de Shopix" \
    || { ko "le commit a échoué"; exit 1; }
  ok "modifications committées"
fi

# Si le dépôt distant contient déjà des commits — un README créé depuis
# l'interface web, par exemple — le premier push serait refusé. On réconcilie
# d'abord les deux historiques.
if git ls-remote --exit-code --heads origin main >/dev/null 2>&1; then
  note "la branche main existe déjà sur le dépôt distant — récupération d'abord"
  git fetch -q origin main 2>/dev/null
  if ! git rebase -q FETCH_HEAD 2>/dev/null; then
    git rebase --abort 2>/dev/null
    if ! git pull -q --rebase --allow-unrelated-histories origin main 2>/dev/null; then
      ko "les deux historiques ne se réconcilient pas automatiquement."
      note "Le plus simple : supprimez le contenu créé depuis l'interface GitHub"
      note "(README, LICENSE, .gitignore), puis relancez ce script."
      exit 1
    fi
  fi
  ok "historique distant intégré"
fi

if git push -u origin main 2>/tmp/ccs-push.log; then
  ok "branche main poussée sur $URL"
else
  echo
  sed 's/^/     /' /tmp/ccs-push.log | head -6
  echo
  ko "le push a échoué — c'est presque toujours l'authentification."
  note "Vérifiez d'abord : gh auth status"
  note "Puis poussez à la main et relancez ce script :"
  echo "     git push -u origin main"
  note "GitHub n'accepte plus le mot de passe de compte : « gh auth login »,"
  note "ou un jeton d'accès personnel (portée « repo ») à sa place."
  echo
  exit 1
fi

# ------------------------------------------------------- 5. l'Application ArgoCD
if ! kubectl -n argocd get deploy argocd-server >/dev/null 2>&1; then
  ko "ArgoCD n'est pas installé — lancez d'abord ./setup/05-argocd.sh"
  exit 1
fi
kubectl apply -f gitops/apps/shopix.yaml >/dev/null || { ko "Application non appliquée"; exit 1; }

attendre_que "ArgoCD synchronise l'application" \
  "kubectl -n argocd get app shopix -o jsonpath='{.status.sync.status}' | grep -q Synced"
attendre_que "l'application est Healthy" \
  "kubectl -n argocd get app shopix -o jsonpath='{.status.health.status}' | grep -q Healthy"

echo
kubectl -n argocd get app shopix \
  -o custom-columns=NOM:.metadata.name,SYNC:.status.sync.status,SANTE:.status.health.status,REVISION:.status.sync.revision
echo
ok "ArgoCD suit maintenant ce dépôt. La démo 10 du J3 est prête."
note "Si l'application reste « Unknown » : kubectl -n argocd logs deploy/argocd-repo-server --tail=30"
note "(c'est là qu'on voit un dépôt injoignable ou une branche qui n'existe pas)"
