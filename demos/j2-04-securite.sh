#!/usr/bin/env bash
# J2 · Module 4 · « RBAC, PSA, Secrets : la preuve » — trois refus instructifs
cd "$(dirname "$0")/.." || exit 1
source lib/demo.sh
exiger kubectl
NS="${NS-shopix}"

titre "Le vigile en action (Module 4 — sécurité intégrée)"

# Table rase : si une répétition précédente s'est arrêtée au milieu de l'étape 2,
# le namespace est resté en « restricted » et le pari de l'étape 2 tombe à plat.
silence "kubectl label ns $NS pod-security.kubernetes.io/enforce=baseline --overwrite"
silence "kubectl -n $NS delete pod nginx-officiel --ignore-not-found --now"

# ------------------------------------------------------------ 1. RBAC
etape 1 "Refus n°1 — qui a le droit de faire quoi"
run "cat k8s/demos/08-rbac-viewer.yaml"
run "kubectl apply -f k8s/demos/08-rbac-viewer.yaml"
dire "Un compte de service, un rôle qui n'autorise que lire les Pods, et le pont entre les deux."

pari "Ce compte peut-il lister les Pods ? Et en créer un ?"
run "kubectl -n $NS auth can-i list pods --as=system:serviceaccount:$NS:stagiaire"
run "kubectl -n $NS auth can-i create pods --as=system:serviceaccount:$NS:stagiaire"
run "kubectl -n $NS auth can-i get secrets --as=system:serviceaccount:$NS:stagiaire"
ok "yes / no / no — sans déployer quoi que ce soit, on a audité les droits."
note "Le « code de sortie 1 » affiché n'est pas une erreur : can-i répond aussi par son"
note "code de retour, ce qui permet de l'utiliser dans un script de contrôle."
dire "auth can-i, c'est l'outil à connaître : il répond avant que l'incident arrive."
note "Et dans l'autre sens : kubectl auth whoami, pour savoir avec quel compte VOUS parlez."

# ------------------------------------------------------------ 2. PSA
etape 2 "Refus n°2 — ce qu'un Pod a le droit d'être"
run "kubectl get ns $NS -o jsonpath='{.metadata.labels}' | tr ',' '\n'"
dire "Ce namespace applique le niveau « baseline ». On passe la barre au cran maximal."
run "kubectl label ns $NS pod-security.kubernetes.io/enforce=restricted --overwrite"

pari "Le nginx officiel, celui que tout le monde déploie. Va-t-il passer ?"
run "kubectl -n $NS delete pod nginx-officiel --ignore-not-found --now >/dev/null; kubectl -n $NS apply -f k8s/demos/09-pod-root.yaml || true"
ko "Refusé à l'admission. Le Pod n'a même pas été créé : l'API a dit non."
dire "La raison est écrite noir sur blanc : il tourne en root, il n'abandonne pas ses capabilities."
dire "Souvenez-vous du Module 2 : « ne pas tourner en root » n'était pas un conseil de style."

pari "Et notre application, Shopix ? Elle a été écrite avec ces contraintes."
run "kubectl -n $NS rollout restart deploy shopix-front"
attendre_que "le front se redéploie en mode restricted" "kubectl -n $NS rollout status deploy shopix-front --timeout=60s"
ok "Shopix passe. Le coût de la conformité se paie à l'écriture du manifeste, pas en production."
run "kubectl label ns $NS pod-security.kubernetes.io/enforce=baseline --overwrite"
note "On revient en baseline pour la suite de la formation."

# ------------------------------------------------------------ 3. Secrets
etape 3 "Refus n°3 — celui qui n'a pas lieu"
run "kubectl -n $NS get secret shopix-paiement"
dire "Type Opaque, une clé. Tout va bien."
pari "Un Secret Kubernetes, c'est chiffré ou encodé ?"
run "kubectl -n $NS get secret shopix-paiement -o jsonpath='{.data.PAIEMENT_CLE}'; echo"
dire "Ça ressemble à quelque chose de protégé. Regardez."
run "kubectl -n $NS get secret shopix-paiement -o go-template='{{.data.PAIEMENT_CLE | base64decode}}'; echo"
ko "Une commande — et kubectl fait le décodage lui-même. Pas de mot de passe, pas de clé : du base64."
dire "Le Secret protège contre l'affichage accidentel, pas contre quelqu'un qui a le droit de lire."
dire "D'où la vraie question : qui a ce droit ? On vient de voir comment y répondre — RBAC."
note "La suite — chiffrement au repos, Vault, External Secrets, secrets éphémères — c'est le Module 8."

echo
titre "Ce qu'on retient"
dire "Trois vigiles différents : RBAC filtre qui parle à l'API, PSA filtre ce qu'un Pod peut être,"
dire "et le Secret… ne filtre rien du tout. Il range."
dire "Moindre privilège : cluster-admin n'est jamais une réponse par défaut."
