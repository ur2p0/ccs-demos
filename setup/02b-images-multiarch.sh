#!/usr/bin/env bash
# Construit Shopix pour DEUX architectures et la pousse dans un registre.
# À n'utiliser que pour le cluster Scaleway : ses nœuds sont en amd64, alors
# qu'un Mac Apple Silicon produit du arm64. Sans ça, les Pods restent bloqués
# en « exec format error » — le symptôme le plus déroutant qui soit.
#
#   REGISTRE=rg.fr-par.scw.cloud/mon-espace ./setup/02b-images-multiarch.sh
cd "$(dirname "$0")/.." || exit 1
source lib/demo.sh
VITESSE=0
TAG="${TAG-1.0.0}"
REGISTRE="${REGISTRE-}"
PLATEFORMES="${PLATEFORMES-linux/amd64,linux/arm64}"

titre "Image Shopix $TAG — multi-architecture"
exiger docker

if [ -z "$REGISTRE" ]; then
  ko "Indiquez le registre de destination."
  echo
  echo "   Scaleway :"
  echo "     1. créez un espace de noms dans Container Registry (console ou CLI)"
  echo "     2. docker login rg.fr-par.scw.cloud -u nologin --password-stdin <<< \"\$SCW_SECRET_KEY\""
  echo "     3. REGISTRE=rg.fr-par.scw.cloud/<votre-espace> $0"
  echo
  echo "   Un manifeste multi-architecture ne peut pas rester en local :"
  echo "   il n'existe que dans un registre. C'est une contrainte de Docker, pas un choix."
  exit 1
fi

if ! docker buildx version >/dev/null 2>&1; then
  ko "docker buildx est nécessaire pour construire plusieurs architectures"
  exit 1
fi

# Un « builder » dédié, capable d'émuler l'autre architecture via QEMU.
if ! docker buildx inspect ccs-multi >/dev/null 2>&1; then
  note "création du constructeur multi-architecture"
  docker buildx create --name ccs-multi --driver docker-container --use >/dev/null || exit 1
else
  docker buildx use ccs-multi
fi
docker buildx inspect --bootstrap >/dev/null 2>&1

CIBLE="$REGISTRE/shopix:$TAG"
note "construction pour : $PLATEFORMES"
note "l'architecture qui n'est pas celle de votre Mac est émulée — comptez 2 à 4 minutes"

docker buildx build \
  --platform "$PLATEFORMES" \
  --tag "$CIBLE" \
  --push \
  shopix || { ko "build ou push en échec"; exit 1; }

ok "poussée : $CIBLE"
echo
note "Vérification du manifeste (les deux architectures doivent apparaître) :"
docker buildx imagetools inspect "$CIBLE" 2>/dev/null | grep -E "Platform|Name:" | head -12

echo
note "Reportez ce nom dans k8s/overlays/scaleway/kustomization.yaml (champ newName) :"
echo "      newName: $REGISTRE/shopix"
