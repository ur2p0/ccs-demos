#!/usr/bin/env bash
# Construit l'image Shopix pour le cluster LOCAL et la charge dans les nœuds.
# L'image produite est celle de votre processeur (arm64 sur Apple Silicon) :
# c'est exactement ce qu'il faut pour Minikube, qui tourne sur la même machine.
# Pour Scaleway (amd64), utilisez ./setup/02b-images-multiarch.sh.
cd "$(dirname "$0")/.." || exit 1
source lib/demo.sh
VITESSE=0
PROFIL="${PROFIL-ccs}"
TAG="${TAG-1.0.0}"

titre "Image Shopix $TAG — construction locale"
exiger docker minikube

ARCH_LOCALE=$(docker info --format '{{.Architecture}}' 2>/dev/null)
note "architecture de construction : ${ARCH_LOCALE:-inconnue}"

docker build -t "shopix:$TAG" shopix || { ko "build en échec"; exit 1; }
TAILLE=$(docker image inspect "shopix:$TAG" --format '{{.Size}}' | awk '{printf "%.0f Mo", $1/1048576}')
PLAT=$(docker image inspect "shopix:$TAG" --format '{{.Os}}/{{.Architecture}}')
ok "image construite : $TAILLE · $PLAT"

note "chargement dans les nœuds du cluster (pas de registre : tout reste local)"
minikube -p "$PROFIL" image load "shopix:$TAG" || { ko "chargement impossible"; exit 1; }
ok "image disponible dans le cluster"

note "Les manifestes locaux utilisent imagePullPolicy: Never — le cluster ne cherchera"
note "jamais cette image ailleurs, et ne pourra donc pas se tromper d'architecture."
