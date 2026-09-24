#!/usr/bin/env bash
# J1 · Module 4 · « 3 réplicas, puis 10 » — clôture de la journée 1
# Deployment, ReplicaSet, Job : la boucle de réconciliation appliquée au calcul.
cd "$(dirname "$0")/.." || exit 1
source lib/demo.sh
exiger kubectl
NS="${NS-shopix}"
exiger_cluster minikube   # ces démonstrations modifient le cluster local, pas Kapsule

titre "3 réplicas, puis 10 (Module 4)"

# Table rase : une répétition précédente a pu laisser le Job, le CronJob, ou
# shopix-api à dix réplicas — l'étape 2 n'aurait alors plus rien à montrer.
silence "kubectl -n $NS delete job facturation --ignore-not-found"
silence "kubectl -n $NS delete cronjob facturation-nuit --ignore-not-found"
silence "kubectl -n $NS scale deploy shopix-api --replicas=2"

etape 1 "Qui commande qui"
run "kubectl -n $NS get deploy,rs,pods -l composant=api"
dire "Le Deployment gère des ReplicaSets, le ReplicaSet gère des Pods. Trois étages, un seul but."

etape 2 "On passe à trois"
run "kubectl -n $NS scale deploy shopix-api --replicas=3"
attendre_que "trois Pods sont prêts" "[ \"\$(kubectl -n $NS get deploy shopix-api -o jsonpath='{.status.readyReplicas}')\" = 3 ]"
run "kubectl -n $NS get pods -l composant=api -o wide"
dire "Trois Pods, répartis sur les nœuds disponibles. Je n'ai pas choisi où."

etape 3 "On en supprime un, encore"
pari "Cette fois, combien de temps avant que le compte soit bon ?"
VICTIME=$(kubectl -n "$NS" get pods -l composant=api -o jsonpath='{.items[0].metadata.name}')
run "kubectl -n $NS delete pod $VICTIME --now && kubectl -n $NS get pods -l composant=api"
ok "Le ReplicaSet n'a pas attendu la fin de la commande pour recréer."

etape 4 "Le Black Friday : de 3 à 10"
pari "Combien de secondes pour passer de 3 à 10 réplicas ?"
run "time kubectl -n $NS scale deploy shopix-api --replicas=10"
attendre_que "les dix Pods sont prêts" "[ \"\$(kubectl -n $NS get deploy shopix-api -o jsonpath='{.status.readyReplicas}')\" = 10 ]"
run "kubectl -n $NS get pods -l composant=api -o wide --no-headers | wc -l"
dire "Ce serait dix machines virtuelles à provisionner. Ici, l'image est déjà là : il ne reste qu'à démarrer des processus."
run "kubectl -n $NS scale deploy shopix-api --replicas=2"

etape 5 "Et ce qui doit finir : la facturation de nuit"
dire "Tout ne tourne pas en permanence. Certains traitements ont vocation à se terminer."
note "on dépose deux commandes en attente, pour que la facturation ait de quoi traiter"
silence "kubectl -n $NS exec deploy/shopix-commandes -- wget -q -O- --post-data='' 'http://127.0.0.1:8080/api/commandes?ref=SHX-101'"
silence "kubectl -n $NS exec deploy/shopix-commandes -- wget -q -O- --post-data='' 'http://127.0.0.1:8080/api/commandes?ref=SHX-102'"
run "kubectl -n $NS delete job facturation --ignore-not-found"
run "kubectl -n $NS apply -f k8s/demos/07-job-facturation.yaml"
pari "Un Deployment redémarre toujours ses Pods. Un Job, lui, va finir dans quel état ?"
attendre_que "le Job se termine" "kubectl -n $NS get job facturation -o jsonpath='{.status.succeeded}' | grep -q 1"
run "kubectl -n $NS get pods -l job-name=facturation"
ok "Completed — et le Pod n'est pas relancé. C'est exactement ce qu'on veut d'un batch."
run "kubectl -n $NS logs job/facturation | tail -4"
note "Le même objet, planifié toutes les nuits, s'appelle un CronJob (voir le manifeste)."

echo
titre "Fin de la journée 1"
dire "Shopix tourne, se répare toute seule, et encaisse dix fois plus de charge en une commande."
dire "Demain : comment elle se fait joindre, où elle range ses données, et qui a le droit de l'approcher."
