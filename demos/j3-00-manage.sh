#!/usr/bin/env bash
# J3 (ou fin J2) · Module 6 · ~12 min · « Shopix chez un fournisseur »
# Les mêmes manifestes qu'en local, réalisés par les services managés du fournisseur
# (Scaleway Kapsule ou Google GKE) : plan de contrôle opéré, nœuds-instances, load
# balancer, disque réseau, registre.
cd "$(dirname "$0")/.." || exit 1
source lib/demo.sh
exiger kubectl
NS="${NS-shopix}"
# Un load balancer managé met une à deux minutes à recevoir son IP, un disque bloc
# 30 à 60 secondes à se détacher puis se rattacher : les 120 s par défaut sont justes.
ATTENTE_MAX="${ATTENTE_MAX-300}"

exiger_cluster manage     # tout l'intérêt est d'être chez le fournisseur
TYPE=$(type_cluster)
F=$(fournisseur "$TYPE")
OVERLAY=$(overlay_cluster "$TYPE")
TAILLE=$(awk '/value: [0-9]+Gi/ {print $2; exit}' "$OVERLAY/kustomization.yaml")
if [ "$TYPE" = "gke" ]; then
  CONSOLE_POOL="Kubernetes Engine → Clusters → ccs-formation → Nœuds : montrez le pool et ses deux VM Compute Engine"
  CONSOLE_LB="Services réseau → Équilibrage de charge"
  CONSOLE_DISQUE="Compute Engine → Disques : montrez le disque pvc-…"
  MAINTENANCE="fenêtre de maintenance quotidienne à 3 h (UTC), canal de versions REGULAR."
  PRIX="Deux nœuds e2-standard-4, un disque et un load balancer : quelques euros par jour ; le plan de contrôle d'un cluster zonal est couvert par le crédit gratuit GKE."
  CONSOLE_FACTURE="Facturation → Rapports (les coûts arrivent avec quelques heures de décalage)"
else
  CONSOLE_POOL="Kubernetes → le pool : montrez les deux instances et l'autohealing"
  CONSOLE_LB="Load Balancers"
  CONSOLE_DISQUE="Block Storage : montrez le volume pvc-…"
  MAINTENANCE="fenêtre de maintenance le dimanche à 3 h."
  PRIX="Deux nœuds DEV1-L ≈ 2,06 €/jour, plus 0,33 €/jour par load balancer ; le disque, quelques centimes."
  CONSOLE_FACTURE="Facturation : affichez la consommation du jour"
fi

# Filet de sécurité : quoi qu'il arrive (q, Ctrl-C, erreur), on rouvre les nœuds et
# on supprime le load balancer de démonstration — sinon un nœud resterait fermé pour
# les démos 9 et 10, et un load balancer serait facturé pour rien.
NOEUD=""
nettoyer() {
  [ -n "$NOEUD" ] && kubectl uncordon "$NOEUD" >/dev/null 2>&1
  kubectl -n "$NS" delete svc vitrine --ignore-not-found --wait=false >/dev/null 2>&1
}
trap nettoyer EXIT

titre "Shopix chez un fournisseur : ce que le managé fait à votre place"

# Table rase : un nœud resté « cordonné » ou une vitrine d'une répétition précédente
for _n in $(kubectl get nodes -o name 2>/dev/null); do silence "kubectl uncordon $_n"; done
silence "kubectl -n $NS delete svc vitrine --ignore-not-found"

# ------------------------------------------------------------ 1. le même YAML
etape 1 "Le même Shopix qu'en local, à trois lignes près"
dire "On compare ce que Kustomize produit pour Minikube et pour $F."
run "diff <(kubectl kustomize k8s/overlays/minikube) <(kubectl kustomize $OVERLAY) | grep '^[<>]'"
dire "L'image vient d'un registre, le disque fait ${TAILLE:-quelques Go} et n'est plus attaché à un nœud, le front a un load balancer."
dire "Tout le reste — Deployments, sondes, NetworkPolicies, RBAC — est strictement identique."

# ------------------------------------------------------------ 2. le plan de contrôle
etape 2 "Où est passé le cerveau ?"
pari "Au J1, on voyait l'api-server et etcd dans kube-system. Et ici ?"
run "kubectl get pods -n kube-system"
ok "Ni api-server, ni etcd, ni scheduler : ils tournent chez $F, hors de notre vue."
dire "On voit le réseau (Cilium — « anetd » chez Google), le DNS, les agents du stockage. Le plan de contrôle, lui, est un service : c'est ça, le managé."
note "La mise à jour de ce plan de contrôle se fait aussi à notre place : $MAINTENANCE"

# ------------------------------------------------------------ 3. les nœuds
etape 3 "Les nœuds sont des instances"
run "kubectl get nodes -L node.kubernetes.io/instance-type -L topology.kubernetes.io/zone"
run "kubectl get nodes -o custom-columns=NOEUD:.metadata.name,INSTANCE:.spec.providerID"
dire "Chaque nœud est une machine virtuelle $F, avec son type, sa zone, son identifiant chez le fournisseur."
pause "console $F → $CONSOLE_POOL, puis Entrée"

# ------------------------------------------------------------ 4. le réseau
etape 4 "Le réseau : un vrai load balancer, commandé par Kubernetes"
run "kubectl -n $NS get svc shopix-front"
dire "Un Service de type LoadBalancer, et une IP publique. Personne n'a ouvert de ticket réseau."
pari "Je déclare un second Service LoadBalancer. Combien de temps avant qu'il ait sa propre IP publique ?"
run "kubectl -n $NS expose deploy shopix-front --name=vitrine --type=LoadBalancer --port=80 --target-port=8080 --labels=demo=vitrine"
attendre_que "$F provisionne un load balancer" \
  "[ -n \"\$(kubectl -n $NS get svc vitrine -o jsonpath='{.status.loadBalancer.ingress[0].ip}')\" ]"
run "kubectl -n $NS get svc vitrine"
run "kubectl -n $NS get events --field-selector involvedObject.name=vitrine --sort-by=.lastTimestamp"
ok "EnsuringLoadBalancer → EnsuredLoadBalancer : le cloud controller manager a appelé l'API $F."
IP_VITRINE=$(kubectl -n "$NS" get svc vitrine -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
note "Boutique par ce nouveau point d'entrée : http://$IP_VITRINE"
pause "ouvrez l'adresse dans le navigateur, puis la console → $CONSOLE_LB, puis Entrée"
run "kubectl -n $NS delete svc vitrine"
dire "Je supprime le Service : le load balancer disparaît aussi chez $F. Et sa facturation avec."

# ------------------------------------------------------------ 5. le stockage
etape 5 "Le stockage : un disque réseau qui suit le Pod"
run "kubectl get storageclass"
run "kubectl get pv -o custom-columns=VOLUME:.metadata.name,TAILLE:.spec.capacity.storage,PILOTE:.spec.csi.driver,RECLAMATION:.spec.persistentVolumeReclaimPolicy"
dire "Le PVC de ${TAILLE:-quelques Go} a été servi par le pilote CSI de $F : c'est un vrai disque réseau, visible dans la console."
run "kubectl -n $NS exec deploy/shopix-commandes -- wget -q -O- --post-data='' 'http://127.0.0.1:8080/api/commandes?ref=SHX-900'; echo"
NOEUD=$(kubectl -n "$NS" get pod -l composant=commandes -o jsonpath='{.items[0].spec.nodeName}')
note "le Pod des commandes et son disque sont sur : $NOEUD"
run "kubectl get volumeattachment -o custom-columns=DISQUE:.spec.source.persistentVolumeName,NOEUD:.spec.nodeName,ATTACHE:.status.attached"
dire "On ferme ce nœud aux nouveaux Pods — le geste d'une maintenance — puis on supprime le Pod."
run "kubectl cordon $NOEUD"
run "kubectl -n $NS delete pod -l composant=commandes --wait=false"
pari "Au J2, en local, le Pod devait revenir sur le même nœud. Ici, il part sur l'autre. Retrouvera-t-il SHX-900 ?"
attendre_que "le disque se détache, se rattache, et le Pod redémarre ailleurs" \
  "kubectl -n $NS get pod -l composant=commandes -o jsonpath='{.items[0].spec.nodeName} {.items[0].status.containerStatuses[0].ready}' | grep -v '^$NOEUD ' | grep -q ' true'"
run "kubectl -n $NS get pod -l composant=commandes -o wide"
run "kubectl get volumeattachment -o custom-columns=DISQUE:.spec.source.persistentVolumeName,NOEUD:.spec.nodeName,ATTACHE:.status.attached"
run "kubectl -n $NS exec deploy/shopix-commandes -- wget -q -O- http://127.0.0.1:8080/api/commandes; echo"
ok "Autre nœud, même disque, même donnée. C'était impossible sur Minikube."
run "kubectl uncordon $NOEUD"
NOEUD=""
pause "console → $CONSOLE_DISQUE, puis Entrée"

# ------------------------------------------------------------ 6. la facture
etape 6 "Et tout cela a un prix"
note "$PRIX"
pause "console → $CONSOLE_FACTURE, puis Entrée"
dire "Le managé ne supprime pas le travail : il le déplace. On paie pour ne plus opérer le plan de contrôle, les disques, le réseau."

echo
titre "Ce qu'on retient"
dire "Les manifestes sont portables ; leur réalisation dépend du fournisseur : load balancer, disque, registre, instances."
dire "C'est la force du managé… et le début de la dépendance : ce qui est portable, c'est le YAML, pas le service qu'il commande."
note "Remise en état : automatique (le nœud est rouvert, la vitrine supprimée)."
