#!/usr/bin/env bash
# J3 · Module 7 · ~10 min · « GitOps en action »
# Le drift provoqué, et la plateforme qui le corrige toute seule.
cd "$(dirname "$0")/.." || exit 1
source lib/demo.sh
exiger kubectl
NS="${NS-shopix}"
# Même raison que pour Grafana : l'accès passe par ./setup/08-acces-j3.sh.
PORT_ARGOCD="${PORT_ARGOCD-8080}"

annoncer_cluster          # Minikube ou Kapsule : on le dit, on n'interdit rien

titre "GitOps en action (Module 7)"

# ------------------------------------------------------------ 1. l'état de référence
etape 1 "Qui décide de ce qui tourne ici ?"
run "kubectl -n argocd get applications"
dire "Synced, Healthy. ArgoCD compare en permanence ce qui est dans Git et ce qui tourne dans le cluster."
note "Interface ArgoCD : http://localhost:$PORT_ARGOCD  (tunnel ./setup/08-acces-j3.sh)"
pause "affichez l'arbre de l'application shopix dans ArgoCD, puis Entrée"
dire "Ce n'est pas un pipeline qui a poussé : c'est un agent, dans le cluster, qui est allé chercher."

# ------------------------------------------------------------ 2. le drift
etape 2 "Le vendredi soir, quelqu'un fait « juste un petit scale »"
run "kubectl -n $NS get deploy shopix-front"
pari "Je passe à cinq réplicas à la main. Combien y en aura-t-il dans une minute ?"
run "kubectl -n $NS scale deploy shopix-front --replicas=5"
run "kubectl -n $NS get pods -l composant=front --no-headers | wc -l"
ok "Cinq. Pour l'instant, le coupable a gagné."

etape 3 "Sauf qu'il y a un témoin"
pause "regardez ArgoCD : l'application vient de passer OutOfSync, puis Entrée"
run "kubectl -n argocd get applications -o custom-columns=NOM:.metadata.name,SYNC:.status.sync.status,SANTE:.status.health.status"
dire "L'écart est détecté, nommé, daté. Et visible par toute l'équipe."

etape 4 "Et il ne se contente pas de regarder"
pari "Auto-heal est activé. Que devient mon scale à cinq ?"
attendre_que "ArgoCD ramène l'état déclaré" "[ \"\$(kubectl -n $NS get deploy shopix-front -o jsonpath='{.spec.replicas}')\" = 2 ]"
run "kubectl -n $NS get deploy shopix-front"
ok "Revenu à deux. Ma modification manuelle a été écrasée — et c'est le comportement souhaité."
dire "La question n'est plus « qui a changé quoi sur le cluster ? » mais « qu'y a-t-il dans Git ? »."
dire "Le cluster n'est plus une source de vérité : c'est une conséquence."

# ------------------------------------------------------------ 3. le bon chemin
etape 5 "Alors comment fait-on, pour de vrai ?"
dire "On ne touche pas au cluster. On change le dépôt."
note "Dans k8s/base/front.yaml, passez replicas de 2 à 3, puis : git commit && git push"
note "ArgoCD scrute le dépôt toutes les 3 minutes — « Refresh » dans l'interface pour ne pas attendre."
pause "faites la modification et poussez-la, puis Entrée"
run "kubectl -n argocd get applications -o custom-columns=NOM:.metadata.name,SYNC:.status.sync.status,REVISION:.status.sync.revision"
dire "Le même mécanisme, dans l'autre sens : Git a bougé, le cluster suit."
ok "Une revue de code, une trace, un auteur, une date. Et un retour arrière qui s'appelle git revert."

echo
titre "Ce qu'on retient"
dire "Le dépôt décrit l'intention, l'agent maintient la réalité. C'est la boucle de réconciliation du J1,"
dire "sortie du cluster et appliquée à la plateforme entière."
note "Reprise : kubectl -n $NS scale deploy shopix-front --replicas=2"
