#!/usr/bin/env bash
# J3 · Module 7 · ~10 min · « La chasse au coupable »
# L'incident du jour : Shopix rame une fois sur cent. Trouvez pourquoi.
cd "$(dirname "$0")/.." || exit 1
source lib/demo.sh
exiger kubectl
NS="${NS-shopix}"
# L'accès passe par le tunnel de ./setup/08-acces-j3.sh : sur macOS, l'IP du
# nœud Minikube n'est pas routable depuis le navigateur.
PORT_GRAFANA="${PORT_GRAFANA-3000}"

titre "Incident du jour : « le site rame, une fois sur cent »"
dire "Un client appelle. Parfois, le paiement met trois secondes. Parfois. Personne ne reproduit."

# ------------------------------------------------------------ 1. le monitoring d'hier
etape 1 "Ce que disait le monitoring d'hier"
run "kubectl top pods -n $NS 2>/dev/null || echo '(metrics-server en cours de démarrage)'"
dire "CPU bas, mémoire basse, aucun redémarrage. Tous les voyants sont au vert."
run "kubectl -n $NS get pods -l composant=api"
ko "Et pourtant le client a raison. Le royaume du « connu » ne détecte que ce qu'on a prévu."

# ------------------------------------------------------------ 2. la moyenne ment
etape 2 "La moyenne, ce mensonge confortable"
note "Grafana : http://localhost:$PORT_GRAFANA — tableau « Shopix — observabilité »"
note "(tunnel ./setup/08-acces-j3.sh · admin / shopix)"
pause "affichez le panneau « Temps de réponse global », puis Entrée"
pari "La p50 est à quelques dizaines de millisecondes. Combien de clients attendent plus de 2 secondes ?"
dire "Regardez l'écart entre la p50 et la p99. La moyenne est bonne. L'expérience de certains clients, non."
dire "Une requête sur cent, sur dix mille commandes par jour, ça fait cent clients mécontents."

# ------------------------------------------------------------ 3. découper par route
etape 3 "Premier découpage : quelle route ?"
pause "affichez le panneau « p99 PAR ROUTE », puis Entrée"
run "echo 'histogram_quantile(0.99, sum by (le, route) (rate(shopix_request_duration_seconds_bucket[5m])))'"
ok "/api/paiement décroche. Le catalogue, lui, est irréprochable."
dire "On vient de diviser le champ de recherche par dix, sans toucher au code."

# ------------------------------------------------------------ 4. découper par Pod
etape 4 "Deuxième découpage : un Pod malade, ou la route elle-même ?"
pari "Si un seul Pod était en cause, que verrait-on sur ce panneau ?"
pause "affichez le panneau « p99 par Pod », puis Entrée"
dire "Tous les Pods décrochent de la même façon. Ce n'est donc pas un Pod : c'est ce que fait cette route."
dire "En l'occurrence, un appel au prestataire de paiement qui part parfois en vrille."

# ------------------------------------------------------------ 5. les logs confirment
etape 5 "La confirmation, dans les journaux"
run "kubectl -n $NS logs -l composant=api --tail=300 --prefix 2>/dev/null | grep -c 'lent' || true"
run "kubectl -n $NS logs -l composant=api --tail=300 2>/dev/null | grep 'lent' | tail -3"
ok "Le message était là depuis le début — noyé dans des milliers de lignes."
dire "Les métriques disent QUE ça va mal et OÙ. Les logs disent POURQUOI. Les traces diraient chez qui."
note "C'est le triptyque du Module 7 : métriques, logs, traces — et le lien entre les trois."

# ------------------------------------------------------------ 6. la facture
etape 6 "Le revers : la cardinalité"
run "kubectl -n $NS get pods -l app=shopix --no-headers | wc -l"
dire "Chaque Pod produit sa propre série temporelle, pour chaque route, pour chaque code de retour."
dire "Multipliez par le nombre de Pods d'une vraie production, qui changent en permanence."
ko "C'est là que la facture d'observabilité explose — et pourquoi VictoriaMetrics existe."

echo
titre "Ce qu'on retient"
dire "On n'a pas deviné : on a découpé. Route, puis Pod, puis journaux."
dire "L'observabilité, ce n'est pas plus de tableaux de bord — c'est la capacité de poser une question qu'on n'avait pas prévue."
