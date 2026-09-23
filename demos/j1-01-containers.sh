#!/usr/bin/env bash
# J1 · Module 2 · 30 min · « En vrai, ça donne quoi ? »
# Épisode 1 du fil rouge : on containerise l'API de Shopix.
# Aucune dépendance à Kubernetes — Docker seul.
cd "$(dirname "$0")/.." || exit 1
source lib/demo.sh
exiger docker

titre "Épisode 1 — on containerise Shopix (Module 2)"
dire "Trois jours durant, on va suivre une boutique en ligne. Elle commence ici, sur mon poste."

# Table rase : sinon un container « shopix-bride » resté de la veille fait échouer
# l'étape 8, et une commande restée dans le volume brouille l'étape 6.
silence "docker rm -f shopix-api shopix-front shopix-bride 2>/dev/null"
silence "docker volume rm -f shopix-donnees 2>/dev/null"
# shopix:1.0.1 n'existe pas encore à ce stade du récit : il naît à l'étape 3.
silence "docker rmi -f shopix:1.0.1 2>/dev/null"
silence "docker network create shopix 2>/dev/null"

# ---------------------------------------------------------------- 1. la recette
etape 1 "La recette : un Dockerfile, ligne à ligne"
dire "Un Dockerfile, ce n'est pas du code : c'est une recette de fabrication, reproductible."
run "cat shopix/Dockerfile"
dire "Base minimale, dépendances d'abord, code ensuite, et un utilisateur qui n'est pas root."

# ---------------------------------------------------------------- 2. le build
etape 2 "On fabrique l'image — et on regarde les couches se créer"
note "on force une construction complète : sinon Docker réutiliserait celle d'hier"
run "docker build --no-cache -t shopix:1.0.0 shopix"
dire "Chaque instruction a produit une couche. Elles sont empilées, et surtout : partagées."
run "docker history shopix:1.0.0 --format 'table {{.CreatedBy}}\t{{.Size}}' | head -12"

note "Pour comparer : la même application, écrite « comme on l'écrit la première fois »"
run "docker build -f shopix/Dockerfile.naif -t shopix:naif shopix"
note "Docker a lui-même émis un avertissement sur ce Dockerfile — lisez-le à la salle :"
note "« JSON arguments recommended for CMD » : en forme shell, le processus ne reçoit pas SIGTERM."
dire "L'outil vous dit qu'il ne saura pas arrêter proprement ce container. On y reviendra au Module 4."
run "docker images shopix --format 'table {{.Repository}}:{{.Tag}}\t{{.Size}}'"
dire "Même application, même comportement. Presque sept fois plus lourde, et bien plus exposée."

# ---------------------------------------------------------------- 3. le cache
etape 3 "On modifie le code, on reconstruit"
dire "Je change une ligne de code, et je reconstruis — cette fois sans rien forcer."
pari "Va-t-il tout refaire comme à l'instant, ou s'arrêter avant ?"
run "sed -i.bak 's/Le e-commerce qui tient la charge/Le e-commerce qui tient la charge ⚓/' shopix/src/server.js"
run "docker build -t shopix:1.0.1 shopix"
dire "Les couches de dépendances sont reprises du cache — CACHED. Seul le code a été recopié."
dire "C'est pour ça qu'on copie package.json AVANT le code : les dépendances changent rarement."
silence "mv shopix/src/server.js.bak shopix/src/server.js"

# ---------------------------------------------------------------- 4. le run
etape 4 "On lance — et on mesure le temps de démarrage"
pari "Combien de secondes entre la commande et une application qui répond ?"
run "docker run -d --name shopix-api --network shopix -p 8081:8080 -e ROLE=api shopix:1.0.0"
run "docker run -d --name shopix-front --network shopix -p 8080:8080 -e ROLE=front -e API_URL=http://shopix-api:8080 shopix:1.0.0"
attendre_que "la boutique répond" "curl -sf localhost:8080/ -o /dev/null"
ok "Boutique ouverte : http://localhost:8080"
dire "Le chiffre affiché, c'est le délai réel entre la commande et la première réponse."
dire "Deux containers qui se parlent par leur nom, sur un réseau privé. Pas d'installation sur ma machine."
pause "ouvrez http://localhost:8080 dans le navigateur, puis Entrée"

# ---------------------------------------------------------------- 5. l'éphémère
etape 5 "Le piège : un container ne retient rien"
run "curl -s -XPOST 'localhost:8081/api/commandes?ref=SHX-003'; echo"
note "la commande vient d'être écrite dans le système de fichiers du container d'API"
run "curl -s localhost:8081/api/commandes; echo"
pari "Je détruis ce container et je le relance. La commande sera-t-elle encore là ?"
run "docker rm -f shopix-api >/dev/null && docker run -d --name shopix-api --network shopix -p 8081:8080 -e ROLE=api shopix:1.0.0"
attendre_que "l'API est de retour" "curl -sf localhost:8081/health -o /dev/null"
run "curl -s localhost:8081/api/commandes; echo"
ko "Liste vide. Tout ce que le container avait écrit est parti avec lui."
dire "Ce n'est pas un bug, c'est le contrat : un container est jetable."

# ---------------------------------------------------------------- 6. le volume
etape 6 "La réponse : sortir la donnée du container"
run "docker volume create shopix-donnees"
run "docker rm -f shopix-api >/dev/null && docker run -d --name shopix-api --network shopix -p 8081:8080 -v shopix-donnees:/data -e DATA_DIR=/data -e ROLE=api shopix:1.0.0"
attendre_que "l'API est prête" "curl -sf localhost:8081/health -o /dev/null"
run "curl -s -XPOST 'localhost:8081/api/commandes?ref=SHX-005'; echo"
pari "Même manipulation : je détruis, je relance. Cette fois ?"
run "docker rm -f shopix-api >/dev/null && docker run -d --name shopix-api --network shopix -p 8081:8080 -v shopix-donnees:/data -e DATA_DIR=/data -e ROLE=api shopix:1.0.0"
attendre_que "l'API est de retour" "curl -sf localhost:8081/health -o /dev/null"
run "curl -s localhost:8081/api/commandes; echo"
ok "La commande a survécu : elle vit dans le volume, pas dans le container."

# ---------------------------------------------------------------- 7. isolation
etape 7 "L'illusion d'être seul au monde"
dire "Depuis l'intérieur, le container croit avoir une machine pour lui."
run "docker exec shopix-api ps"
dire "Un seul processus utile, et il porte le PID 1. Vu du moteur, c'est un processus parmi les autres."
run "docker top shopix-api"
dire "Même processus, deux numéros : c'est un namespace PID. L'isolation est une vue, pas un mur."
note "Sur un Mac, ce « moteur » est une machine virtuelle Linux — le noyau partagé est le sien, pas celui de macOS."

# ---------------------------------------------------------------- 8. limites
etape 8 "Et la limite qu'on pose soi-même"
run "docker run -d --name shopix-bride -p 8082:8080 --memory=96m -e ROLE=api shopix:1.0.0"
attendre_que "le container bridé répond" "curl -sf localhost:8082/health -o /dev/null"
pari "Je lui demande d'allouer 300 Mo alors qu'il a droit à 96. Que va-t-il se passer ?"
run "curl -s -m 5 'localhost:8082/leak?mo=300' || true"
run "docker inspect shopix-bride --format 'statut={{.State.Status}} · code={{.State.ExitCode}} · tué_faute_de_mémoire={{.State.OOMKilled}}'"
ko "OOMKilled : le noyau a tranché. C'est un cgroup — et c'est ce qui rend le multi-tenant possible."

echo
titre "Ce qu'on retient"
dire "Simple, rapide, reproductible — et jetable par construction."
dire "Mais : la donnée, le réseau, les limites, le redémarrage… tout ça, je l'ai fait à la main."
dire "À dix containers ça va. À trois cents, il faut quelqu'un dont c'est le métier : l'orchestrateur."
note "nettoyage : ./demos/reset.sh --docker"
