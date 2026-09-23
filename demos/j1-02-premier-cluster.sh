#!/usr/bin/env bash
# J1 · Module 4 · 10 min · « Le paysage, puis un cluster »
# Démo flash de transition : l'ampleur de l'écosystème, puis un vrai cluster qui répond.
cd "$(dirname "$0")/.." || exit 1
source lib/demo.sh
exiger kubectl minikube
PROFIL="${PROFIL-ccs}"

titre "Le paysage, puis un cluster (Module 4)"

etape 1 "L'écosystème, en une image"
pari "À votre avis, combien de projets sont recensés sur la CNCF Landscape ?"
note "Ouvrez landscape.cncf.io — et vérifiez le chiffre le matin même."
pause "affichez la page au vidéoprojecteur, puis Entrée"
dire "Voilà le vertige. La bonne nouvelle : on ne retiendra qu'une colonne vertébrale."

etape 2 "Un cluster, ça se fabrique en une commande"
dire "Je l'ai lancée ce matin. Elle a mis quatre-vingt-dix secondes."
run "echo 'minikube start -p $PROFIL --nodes=2 --cni=calico --cpus=4 --memory=6g'"
run "minikube -p $PROFIL status"

etape 3 "Premier contact"
pari "Qu'est-ce que kubectl va me répondre : des serveurs, des machines virtuelles, autre chose ?"
run "kubectl get nodes -o wide"
dire "Deux nœuds. Notez la colonne OS et la colonne runtime : containerd, pas Docker."
dire "Kubernetes ne sait rien de mon Mac. Il voit des nœuds, et il ne veut rien savoir d'autre."

run "kubectl cluster-info"
run "kubectl get namespaces"
dire "kube-system, c'est la salle des machines. On y va tout de suite."

echo
titre "Transition"
dire "Un cluster, c'est deux choses : un cerveau qui décide, et des nœuds qui exécutent."
dire "On va ouvrir le cerveau."
