#!/usr/bin/env bash
# J1 · Module 4 · « Le cerveau en action » — montrer l'invisible
# On regarde le control plane travailler, puis on le met à l'épreuve.
cd "$(dirname "$0")/.." || exit 1
source lib/demo.sh
exiger kubectl
NS="${NS-shopix}"

titre "Le cerveau en action (Module 4)"

etape 1 "Les nœuds : ce que Kubernetes accepte de savoir"
run "kubectl get nodes -o wide"
dire "Le système d'exploitation de l'hôte est une ligne d'inventaire. Rien de plus."

etape 2 "La salle des machines"
run "kubectl get pods -n kube-system -o wide"
dire "api-server : l'unique porte d'entrée. scheduler : le placeur. controller-manager : le gardien."
dire "etcd : la mémoire. Et sur chaque nœud, kubelet et le CNI."
note "Tous ces composants sont eux-mêmes… des Pods."

etape 3 "Le désir, écrit quelque part"
run "kubectl -n $NS get deploy shopix-front -o jsonpath='{.spec.replicas}'; echo ' réplicas demandés'"
run "kubectl -n $NS get pods -l composant=front -o wide"
dire "Deux demandés, deux en vie. Pour l'instant, le monde est en ordre."

etape 4 "On casse"
pari "Je supprime un Pod, sauvagement. Que se passe-t-il dans les deux secondes qui suivent ?"
VICTIME=$(kubectl -n "$NS" get pods -l composant=front -o jsonpath='{.items[0].metadata.name}')
note "victime désignée : $VICTIME"
run "kubectl -n $NS delete pod $VICTIME --now"
run "kubectl -n $NS get pods -l composant=front -o wide"
ok "Un nouveau Pod, un nouveau nom, une nouvelle IP — et toujours deux réplicas."
dire "Personne ne m'a demandé mon avis. Le controller a vu l'écart entre deux (voulu) et un (réel)."
dire "Il n'a pas réparé le Pod : il l'a remplacé. C'est toute la différence avec une VM."

etape 5 "La trace de la décision"
run "kubectl -n $NS get events --sort-by=.lastTimestamp | tail -8"
dire "Scheduled, Pulled, Created, Started : la chaîne de décision, horodatée."

etape 6 "La même chose, en couleur"
note "k9s : la vue de contrôle qu'on garde ouverte toute la journée"
pause "lancez « k9s -n $NS » dans un second terminal, montrez la vue Pods, puis Entrée"

echo
titre "Ce qu'on retient"
dire "On ne pilote pas Kubernetes : on lui déclare une intention, et il la maintient."
dire "Boucle de réconciliation — c'est le seul concept à retenir de cette demi-journée."
