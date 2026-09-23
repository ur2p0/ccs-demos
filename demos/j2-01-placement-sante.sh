#!/usr/bin/env bash
# J2 · Module 4 · « OOMKilled, Pending, et sondes »
# Quatre mini-scénarios pour toucher du doigt le placement et la santé.
cd "$(dirname "$0")/.." || exit 1
source lib/demo.sh
exiger kubectl
NS="${NS-shopix}"

titre "Incident du jour : cette nuit, un Pod a mangé toute la RAM d'un nœud"

# Table rase : taints, déploiements de démonstration et sondes cassées survivent
# à une répétition précédente et faussent les quatre scénarios.
silence "kubectl -n $NS delete deploy shopix-paiement shopix-etale --ignore-not-found"
silence "kubectl -n $NS delete pod shopix-gourmand --ignore-not-found --now"
for _noeud in $(kubectl get nodes -o name 2>/dev/null); do
  silence "kubectl taint $_noeud paiement=true:NoSchedule- 2>/dev/null"
done
silence "kubectl -n $NS exec deploy/shopix-api -- wget -q -O- http://127.0.0.1:8080/admin/reparer"

# ------------------------------------------------------------ 1. OOMKilled
etape 1 "Scénario 1 — le Pod glouton"
run "kubectl -n $NS delete pod shopix-gourmand --ignore-not-found --now"
run "grep -A2 'limits' k8s/demos/01-oomkill.yaml | head -4"
dire "Quatre-vingt-seize mégaoctets. Pas un de plus."
run "kubectl -n $NS apply -f k8s/demos/01-oomkill.yaml"
attendre_que "le Pod glouton répond" "kubectl -n $NS get pod shopix-gourmand -o jsonpath='{.status.phase}' | grep -q Running"
pari "Je lui demande d'allouer 300 Mo. Va-t-il ramer, planter, ou être tué ?"
run "kubectl -n $NS exec shopix-gourmand -- wget -q -T 5 -O- 'http://127.0.0.1:8080/leak?mo=300' || true; echo"
note "« exit code 137 » : 128 + 9, c'est-à-dire tué par SIGKILL. C'est la preuve, pas une panne."
sleep 3
run "kubectl -n $NS get pod shopix-gourmand"
run "kubectl -n $NS get pod shopix-gourmand -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}'; echo"
ko "OOMKilled. Pas de négociation : la limite est un plafond, pas une suggestion."
dire "Et notez : le Pod redémarre. RestartPolicy Always. Il va boucler tant que le code fuit."
run "kubectl -n $NS get pod shopix-gourmand -o jsonpath='{.status.containerStatuses[0].restartCount}'; echo ' redémarrage(s)'"
note "CrashLoopBackOff, c'est ça : Kubernetes qui réessaie en espaçant les tentatives."
run "kubectl -n $NS delete pod shopix-gourmand --now"

# ------------------------------------------------------------ 2. taint
etape 2 "Scénario 2 — le quai réservé"
QUAI=$(kubectl get nodes -l zone=paiement -o jsonpath='{.items[0].metadata.name}')
dire "On réserve un nœud aux traitements de paiement. Personne d'autre n'y accoste."
run "kubectl taint nodes $QUAI paiement=true:NoSchedule --overwrite"
run "kubectl -n $NS apply -f k8s/demos/02-taint-pending.yaml"
pari "Ce déploiement vise ce nœud, sans laissez-passer. Pending, ou CrashLoop ?"
sleep 4
run "kubectl -n $NS get pods -l composant=paiement"
run "kubectl -n $NS describe pod -l composant=paiement | grep -A3 Events | tail -4"
ko "Pending. Le scheduler n'a trouvé aucun nœud acceptable — il attend, indéfiniment."
dire "Un Pod Pending n'est pas en panne : il est en file d'attente."

pari "J'ajoute la toleration. Combien de temps avant qu'il démarre ?"
run "kubectl -n $NS apply -f k8s/demos/03-taint-toleration.yaml"
attendre_que "le Pod de paiement démarre" "kubectl -n $NS get pods -l composant=paiement -o jsonpath='{.items[*].status.phase}' | grep -q Running"
run "kubectl -n $NS get pods -l composant=paiement -o wide"
ok "Le taint repousse, la toleration autorise. Ce sont deux moitiés du même contrat."

# ------------------------------------------------------------ 3. anti-affinité
etape 3 "Scénario 3 — ne pas mettre tous ses œufs sur le même nœud"
run "kubectl -n $NS apply -f k8s/demos/04-antiaffinite.yaml"
pari "Trois réplicas, deux nœuds, et l'interdiction d'en partager un. Résultat ?"
sleep 5
run "kubectl -n $NS get pods -l composant=etale -o wide"
ko "Deux placés, un Pending : la règle est stricte, le scheduler préfère attendre que la violer."
dire "C'est le bon réflexe en production — mais il faut alors assez de nœuds. Ici, c'est la démonstration du coût de la règle."
run "kubectl -n $NS delete -f k8s/demos/04-antiaffinite.yaml"

# ------------------------------------------------------------ 4. sondes
etape 4 "Scénario 4 — un Pod vivant, mais pas en état de servir"
run "kubectl -n $NS get endpoints shopix-api"
note "L'avertissement de dépréciation est un point de cours : v1 Endpoints est remplacé par"
note "EndpointSlice, qui découpe la liste en tranches — indispensable au-delà de quelques centaines de Pods."
dire "Deux adresses derrière le Service : les deux Pods sont prêts."
CIBLE=$(kubectl -n "$NS" get pods -l composant=api -o jsonpath='{.items[0].metadata.name}')
note "on va rendre malade : $CIBLE"
pari "Je casse sa sonde de readiness — pas sa liveness. Va-t-il être tué, ou juste mis de côté ?"
run "kubectl -n $NS exec $CIBLE -- wget -q -O- 'http://127.0.0.1:8080/admin/casser?cible=ready'; echo"
sleep 6
run "kubectl -n $NS get pods -l composant=api"
run "kubectl -n $NS get endpoints shopix-api"
ok "Le Pod est toujours Running, mais il a disparu des endpoints : plus aucun trafic pour lui."
dire "Readiness : « je ne suis pas en état de répondre ». Liveness : « je suis mort, tuez-moi »."
dire "Confondre les deux, c'est soit router des clients vers un service malade, soit tuer un Pod qui démarrait lentement."

pari "Et si je casse la liveness ?"
run "kubectl -n $NS exec $CIBLE -- wget -q -O- 'http://127.0.0.1:8080/admin/casser?cible=live' || true; echo"
attendre_que "le Pod redémarre" "[ \"\$(kubectl -n $NS get pod $CIBLE -o jsonpath='{.status.containerStatuses[0].restartCount}')\" != 0 ]"
run "kubectl -n $NS get pod $CIBLE"
ok "Redémarré. Le container a été tué et relancé — l'état interne est reparti à zéro, et la sonde repasse."

echo
titre "Ce qu'on retient"
dire "Requests et limits décident du placement et du couperet."
dire "Taints, tolerations et affinités décident du où."
dire "Les sondes décident du quand : quand recevoir du trafic, quand être relancé."
note "nettoyage de cette démo : ./demos/reset.sh --j2"
