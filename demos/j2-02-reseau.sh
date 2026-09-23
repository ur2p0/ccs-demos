#!/usr/bin/env bash
# J2 · Module 4 · « Le réseau, sans les mains »
# Services, DNS, Ingress et Zero-Trust.
cd "$(dirname "$0")/.." || exit 1
source lib/demo.sh
exiger kubectl
NS="${NS-shopix}"
PROFIL="${PROFIL-ccs}"

titre "Le réseau, sans les mains (Module 4)"

# Table rase : une NetworkPolicy laissée par une répétition précédente rend les
# étapes 2, 3 et 5 muettes (tout tombe en délai dépassé) et fait afficher
# « unchanged » au lieu de « created » aux étapes 6 et 7 — la démonstration ne
# montre alors plus rien du tout.
silence "kubectl -n $NS delete netpol --all"
silence "kubectl -n $NS apply -f k8s/demos/tools.yaml"
attendre_que "la boîte à outils est prête" "kubectl -n $NS get pod tools -o jsonpath='{.status.phase}' | grep -q Running"

# ------------------------------------------------------------ 1. IP par Pod
etape 1 "Chaque Pod a son IP — et elle ne vaut rien"
run "kubectl -n $NS get pods -l composant=api -o custom-columns=POD:.metadata.name,IP:.status.podIP,NOEUD:.spec.nodeName"
dire "Des IP routables dans tout le cluster, sans NAT. Mais elles changent à chaque renaissance."
VICTIME=$(kubectl -n "$NS" get pods -l composant=api -o jsonpath='{.items[0].metadata.name}')
run "kubectl -n $NS delete pod $VICTIME --now >/dev/null && kubectl -n $NS get pods -l composant=api -o custom-columns=POD:.metadata.name,IP:.status.podIP"
ko "Nouvelle IP. Coder en dur l'adresse d'un Pod, c'est coder en dur un numéro qui va changer."

# ------------------------------------------------------------ 2. Service + DNS
etape 2 "Le Service : un nom stable pour des Pods qui bougent"
run "kubectl -n $NS get svc shopix-api"
dire "Avant de résoudre : regardons la configuration DNS que le Pod a reçue."
run "kubectl -n $NS exec tools -- cat /etc/resolv.conf"
note "search : trois suffixes, essayés dans cet ordre. ndots:5 : un nom qui contient"
note "moins de cinq points est considéré comme court, donc complété par ces suffixes."
pari "Depuis un autre Pod, que va donner un appel à « shopix-api » tout court ?"
run "kubectl -n $NS exec tools -- nslookup shopix-api"
note "Le premier suffixe répond. Les NXDOMAIN qui suivent sont les suffixes suivants,"
note "tentés inutilement : c'est le prix de la commodité, et vos applications le paient aussi."
note "Et le « code de sortie 1 » vient de là : busybox sort en erreur dès qu'un suffixe échoue,"
note "même quand le nom a été résolu. Ce n'est pas un échec de résolution."
run "kubectl -n $NS exec tools -- wget -q -O- http://shopix-api:8080/whoami; echo"
ok "Résolu par CoreDNS, routé par le Service. Je n'ai jamais écrit une seule IP."
dire "L'adresse du quai, pas celle du navire : peu importe quel Pod y est amarré aujourd'hui."

etape 3 "Et la répartition, elle est où ?"
dire "Dix appels d'affilée : regardez le nom du Pod qui répond."
run "for i in 1 2 3 4 5 6 7 8 9 10; do kubectl -n $NS exec tools -- wget -q -O- http://shopix-api:8080/whoami 2>/dev/null | grep -o '\"pod\": \"[^\"]*\"'; done"
ok "Deux Pods se partagent le trafic. C'est kube-proxy, et personne ne l'a configuré."

# ------------------------------------------------------------ 3. Ingress
etape 4 "Sortir du cluster : un seul point d'entrée pour tout le monde"
run "kubectl -n $NS get ingress shopix"
dire "Une règle : la racine va au front, /api va à l'API. Un seul répartiteur, plusieurs applications."
if [ "$(uname -s)" = "Darwin" ]; then
  note "Boutique : http://shopix.local:8888  (tunnel ./setup/07-acces.sh)"
else
  note "Boutique : http://shopix.local:30080  (nœud $(minikube -p "$PROFIL" ip 2>/dev/null))"
fi
pause "montrez la boutique dans le navigateur, rechargez deux ou trois fois, puis Entrée"
dire "En haut de page, le nom du Pod qui a servi la requête change : la répartition est visible à l'œil nu."

# ------------------------------------------------------------ 4. Zero-Trust
etape 5 "Par défaut, tout le monde parle à tout le monde"
run "kubectl -n $NS exec tools -- wget -q -T 3 -O- http://shopix-api:8080/api/produits | head -c 120; echo"
dire "Ce Pod n'a rien à faire avec l'API de paiement. Et pourtant, il l'interroge sans difficulté."

etape 6 "On ferme tout"
run "cat k8s/demos/05-netpol-deny.yaml"
pari "J'applique un deny-all sur l'API. Le front va-t-il continuer à afficher le catalogue ?"
run "kubectl -n $NS apply -f k8s/demos/05-netpol-deny.yaml"
sleep 3
run "kubectl -n $NS exec tools -- wget -q -T 5 -O- http://shopix-api:8080/api/produits || echo '↑ délai dépassé — le paquet est jeté, pas refusé'"
pause "rechargez la boutique : le bandeau « catalogue indisponible » doit apparaître, puis Entrée"
ko "Le front est vivant, l'API est vivante — mais elles ne se parlent plus."
dire "Une Network Policy ne refuse pas : elle ignore. D'où le timeout, et non l'erreur immédiate."

etape 7 "On rouvre, nominativement"
run "cat k8s/demos/06-netpol-allow-front.yaml"
pari "J'autorise le front. Le Pod « tools », lui, va-t-il repasser aussi ?"
run "kubectl -n $NS apply -f k8s/demos/06-netpol-allow-front.yaml"
sleep 3
pause "rechargez la boutique : le catalogue doit être revenu, puis Entrée"
run "kubectl -n $NS exec tools -- wget -q -T 5 -O- http://shopix-api:8080/api/produits || echo '↑ toujours dehors'"
ok "Le front passe, l'outil reste dehors. La règle est nominative, pas générale."
dire "C'est ça, le Zero-Trust : on n'ouvre pas un réseau, on ouvre un flux identifié."

echo
titre "Ce qu'on retient"
dire "Un nom stable, une répartition gratuite, un point d'entrée unique, et des flux déclarés."
dire "Le rayon d'impact d'un Pod compromis, c'est exactement ce que vous avez autorisé."
note "pour lever les règles : kubectl -n $NS delete netpol --all"
