#!/usr/bin/env bash
# J2 · Module 4 · « La donnée qui survit au Pod » — le crash test
# Le contraste entre shopix-api (éphémère) et shopix-commandes (avec volume).
cd "$(dirname "$0")/.." || exit 1
source lib/demo.sh
exiger kubectl
NS="${NS-shopix}"

titre "La donnée qui survit au Pod (Module 4)"

# ------------------------------------------------------------ 1. l'éphémère
etape 1 "Rappel de la règle : sans volume, rien ne survit"
dire "shopix-api n'a aucun volume. Elle écrit dans son propre système de fichiers."
run "kubectl -n $NS exec deploy/shopix-api -- wget -q -O- --post-data='' 'http://127.0.0.1:8080/api/commandes?ref=SHX-001'; echo"
run "kubectl -n $NS exec deploy/shopix-api -- wget -q -O- http://127.0.0.1:8080/api/commandes; echo"
pari "Deux Pods servent cette API. Le deuxième voit-il cette commande ?"
run "kubectl -n $NS get pods -l composant=api -o name"
run "for p in \$(kubectl -n $NS get pods -l composant=api -o name); do echo \"--- \$p\"; kubectl -n $NS exec \$p -- wget -q -O- http://127.0.0.1:8080/api/commandes; echo; done"
ko "Chaque Pod a sa propre vérité. C'est exactement le problème que le stockage partagé résout."

# ------------------------------------------------------------ 2. la demande
etape 2 "La réservation : PVC, PV, StorageClass"
run "kubectl -n $NS get pvc shopix-commandes"
dire "Le développeur a réservé un Go. Il n'a jamais su d'où il viendrait."
run "kubectl get storageclass"
dire "Le catalogue des entrepôts du port : c'est la plateforme qui le tient."
run "kubectl -n $NS get pv | head -3"
dire "Et voilà l'entrepôt affecté. Provisionné automatiquement — personne n'a créé de disque à la main."

# ------------------------------------------------------------ 3. le crash test
etape 3 "On écrit une vraie commande"
run "kubectl -n $NS exec deploy/shopix-commandes -- wget -q -O- --post-data='' 'http://127.0.0.1:8080/api/commandes?ref=SHX-003'; echo"
run "kubectl -n $NS exec deploy/shopix-commandes -- wget -q -O- http://127.0.0.1:8080/api/commandes; echo"
POD=$(kubectl -n "$NS" get pods -l composant=commandes -o jsonpath='{.items[0].metadata.name}')
note "le Pod qui détient la donnée : $POD"

pari "Je supprime ce Pod. La commande sera-t-elle encore là après ?"
run "kubectl -n $NS delete pod $POD --now"
attendre_que "un nouveau Pod a pris le relais" "kubectl -n $NS get deploy shopix-commandes -o jsonpath='{.status.readyReplicas}' | grep -q 1"
run "kubectl -n $NS get pods -l composant=commandes"
dire "Autre nom, autre IP, autre container. Et pourtant…"
run "kubectl -n $NS exec deploy/shopix-commandes -- wget -q -O- http://127.0.0.1:8080/api/commandes; echo"
ok "La commande a survécu. Le Pod est jetable, le volume ne l'est pas."

# ------------------------------------------------------------ 4. le détail qui fait le cours
etape 4 "Pourquoi ce Pod revient toujours sur le même nœud"
run "kubectl -n $NS get pods -l composant=commandes -o custom-columns=POD:.metadata.name,NOEUD:.spec.nodeName"
run "grep -A2 nodeSelector k8s/base/commandes.yaml | head -3"
dire "En local, ce volume est un répertoire du nœud. Si le Pod part ailleurs, il trouve un dossier vide."
dire "D'où le ReadWriteOnce : un seul nœud peut monter ce disque à la fois."
note "Sur un cloud, le disque est un volume réseau : il se détache et se rattache, et le Pod peut bouger."
note "C'est la seule vraie différence entre ce cluster local et le cluster Scaleway."

# ------------------------------------------------------------ 5. le batch qui lit la même donnée
etape 5 "Et la facturation de nuit lit le même entrepôt"
run "kubectl -n $NS delete job facturation --ignore-not-found >/dev/null; kubectl -n $NS apply -f k8s/demos/07-job-facturation.yaml"
attendre_que "la facturation se termine" "kubectl -n $NS get job facturation -o jsonpath='{.status.succeeded}' | grep -q 1"
run "kubectl -n $NS logs job/facturation | tail -3"
ok "Un autre Pod, un autre cycle de vie — la même donnée."

echo
titre "Ce qu'on retient"
dire "Le développeur réserve, la plateforme tient le catalogue, l'infrastructure affecte l'entrepôt."
dire "Et la vraie question de production n'est pas « comment », c'est « que se passe-t-il quand on supprime la réservation »."
note "La règle de rétention — Retain ou Delete — est une décision, pas un détail."
