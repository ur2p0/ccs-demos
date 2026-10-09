#!/usr/bin/env bash
# J3 · Module 8 · ~10 min · « L'alarme » — la détection à l'exécution avec Falco
# Kyverno a contrôlé ce qui entre. Falco surveille ce qui se passe une fois le Pod lancé :
# il lit les appels système du noyau (eBPF) et les confronte à des règles.
#
#   ./demos/j3-04-falco.sh                la démonstration (installe Falco s'il manque)
#   ./demos/j3-04-falco.sh --preparer     installe seulement Falco (~2 min, à faire à la pause)
#   ./demos/j3-04-falco.sh --desinstaller retire Falco du cluster
cd "$(dirname "$0")/.." || exit 1
source lib/demo.sh
exiger kubectl helm
NS="${NS-shopix}"
ATTENTE_MAX="${ATTENTE_MAX-300}"
JOURNAUX="kubectl -n falco logs -l app.kubernetes.io/name=falco -c falco --since=90s --tail=300"
# Les alertes de Falco commencent par l'heure puis la priorité : on ne garde que celles-là.
FILTRE="grep -E ' (Emergency|Alert|Critical|Error|Warning|Notice) ' | tail -4"

installer_falco() {
  if kubectl -n falco get ds falco >/dev/null 2>&1; then
    ok "Falco est déjà installé"
  else
    note "installation de Falco (chart Helm officiel, pilote eBPF moderne, ~2 min)"
    helm repo add falcosecurity https://falcosecurity.github.io/charts >/dev/null 2>&1
    helm repo update falcosecurity >/dev/null 2>&1
    helm upgrade --install falco falcosecurity/falco -n falco --create-namespace \
      --set driver.kind=modern_ebpf --set tty=true --wait --timeout 6m >/dev/null \
      || { ko "installation de Falco impossible (réseau ? noyau sans eBPF moderne ?)"; exit 1; }
    ok "Falco installé : un Pod par nœud (DaemonSet)"
  fi
  attendre_que "Falco tourne sur tous les nœuds" "kubectl -n falco rollout status ds/falco --timeout=10s"
}

case "${1-}" in
  --preparer)     titre "Préparation : Falco"; annoncer_cluster; installer_falco; exit 0 ;;
  --desinstaller) titre "Retrait de Falco"
                  helm uninstall falco -n falco && kubectl delete ns falco --ignore-not-found
                  ok "Falco retiré"; exit 0 ;;
esac

# Filet : l'« outil » déposé dans /tmp disparaît avec le Pod ; on remplace le Pod à la fin
# pour repartir d'une image propre — exactement ce qu'on ferait après un incident.
# On supprime les Pods (le ReplicaSet les recrée) plutôt qu'un rollout restart : la spec ne change
# pas, donc ArgoCD n'y voit aucune dérive sur le cluster managé.
nettoyer() { kubectl -n "$NS" delete pod -l composant=api --wait=false >/dev/null 2>&1; }

annoncer_cluster
if [ "$(type_cluster)" = "minikube" ]; then
  note "Sur Minikube (Docker Desktop), le pilote eBPF de Falco dépend du noyau de la VM : non garanti."
  note "La démonstration est prévue pour un cluster managé (Kapsule ou GKE)."
fi
titre "L'alarme : la détection à l'exécution (Module 8)"
installer_falco
trap nettoyer EXIT

# ------------------------------------------------------------ 1. le contexte
etape 1 "Tout ce qui tourne a passé l'admission. Et après ?"
run "kubectl -n falco get pods -o wide"
dire "Un Pod Falco par nœud. Il ne regarde pas les manifestes : il regarde le noyau, appel système par appel système."
dire "Kyverno a contrôlé ce qui entre. Falco surveille ce qui se passe une fois dedans."
note "Dans un second terminal, laissez défiler les alertes :"
echo "     kubectl -n falco logs -f -l app.kubernetes.io/name=falco -c falco --max-log-requests=10"
pause "lancez-le à côté, puis Entrée"

# ------------------------------------------------------------ 2. le shell
etape 2 "Quelqu'un ouvre un shell dans un Pod de production"
pari "Je me contente de lancer « id » dans le container de l'API. Falco va-t-il réagir ?"
run "kubectl -n $NS exec -it deploy/shopix-api -- sh -c 'id; hostname'"
sleep 2
run "$JOURNAUX | grep -i 'shell' | $FILTRE"
ok "« A shell was spawned in a container with an attached terminal » — qui, quel Pod, quelle commande."
dire "Un shell interactif en production, c'est soit un opérateur qui débogue, soit un attaquant. Dans les deux cas, on veut le savoir."

# ------------------------------------------------------------ 3. la chasse aux clés
etape 3 "Puis il cherche des clés"
run "kubectl -n $NS exec deploy/shopix-api -- find / -name id_rsa 2>/dev/null; echo '(recherche terminée)'"
sleep 2
run "$JOURNAUX | grep -iE 'private key|password' | $FILTRE"
ok "Aucune clé trouvée — mais la recherche elle-même est un signal : c'est un comportement d'attaquant."

# ------------------------------------------------------------ 4. le binaire déposé
etape 4 "Et il dépose son propre outil"
pari "Je copie un exécutable dans /tmp et je le lance. Autorisé ? Détecté ?"
run "kubectl -n $NS exec deploy/shopix-api -- sh -c 'cp /bin/busybox /tmp/outil && /tmp/outil whoami'"
sleep 2
run "$JOURNAUX | grep -iE 'not part of base image|upper layer|drop and execute' | $FILTRE"
ko "Autorisé — rien ne l'interdit dans ce container. Mais détecté : ce binaire n'existait pas dans l'image."
dire "Souvenez-vous du Module 2 : l'image est immuable. Tout exécutable qui n'y était pas est suspect par définition."
note "La prévention, c'est readOnlyRootFilesystem : avec lui, le cp aurait échoué. Falco détecte, il n'empêche pas."

echo
titre "Ce qu'on retient"
dire "Trois lignes de défense : au build (scan, signature), à l'admission (PSA, Kyverno), à l'exécution (Falco)."
dire "Falco observe et alerte ; il n'empêche pas. On branche ses alertes sur le SIEM ou la messagerie (falcosidekick)."
dire "Et après un incident, on ne soigne pas le Pod : on le remplace. C'est ce que le script fait maintenant."
note "Remise en état : les Pods de shopix-api sont remplacés (image propre, /tmp vide). Falco reste installé : ./demos/j3-04-falco.sh --desinstaller"
