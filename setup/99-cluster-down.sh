#!/usr/bin/env bash
# Éteint (ou supprime) le cluster de démonstration.
cd "$(dirname "$0")/.." || exit 1
source lib/demo.sh
VITESSE=0
PROFIL="${PROFIL-ccs}"

titre "Arrêt du cluster « $PROFIL »"
if [ "${1-}" = "--supprimer" ]; then
  minikube delete -p "$PROFIL" && ok "cluster supprimé (il faudra tout remonter)"
else
  minikube stop -p "$PROFIL" && ok "cluster arrêté — « minikube start -p $PROFIL » le réveille en 1 minute"
  note "pour tout effacer : $0 --supprimer"
fi
