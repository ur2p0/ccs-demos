#!/usr/bin/env bash
# Petite bibliothèque d'animation de démonstrations — formation CCS.
# Compatible bash 3.2 (celui de macOS). Aucune dépendance.
#
# Dans un script de démo :
#   source "$(dirname "$0")/../lib/demo.sh"
#   titre "Ma démo"
#   etape 1 "On regarde ce qui tourne"
#   dire "Ici je commente ce que la salle va voir"
#   pari "Combien de Pods vont apparaître ?"
#   run kubectl get pods
#
# Variables utiles :
#   VITESSE=0      désactive l'effet machine à écrire (par défaut 0.012 s/caractère)
#   SANS_PAUSE=1   enchaîne tout sans attendre de touche (répétition, test)

# Pas de « pipefail » ici, volontairement. Beaucoup d'outils répondent
# correctement tout en sortant en code non nul : « kubectl auth can-i » sort en 1
# quand la réponse est « no », busybox nslookup sort en 1 quand il n'y a pas
# d'enregistrement AAAA. Avec pipefail, « outil | grep » échouerait alors même
# que grep a trouvé ce qu'on cherchait — on passerait notre temps à débugger des
# faux négatifs.
set -u

if [ -t 1 ]; then
  C_TITRE=$'\033[1;38;5;23m'; C_ETAPE=$'\033[1;38;5;29m'; C_CMD=$'\033[1;37m'
  C_DIRE=$'\033[2;37m'; C_PARI=$'\033[1;38;5;173m'; C_OK=$'\033[38;5;29m'
  C_KO=$'\033[38;5;167m'; C_GRIS=$'\033[2m'; C_RAZ=$'\033[0m'
else
  C_TITRE=""; C_ETAPE=""; C_CMD=""; C_DIRE=""; C_PARI=""; C_OK=""; C_KO=""; C_GRIS=""; C_RAZ=""
fi

VITESSE="${VITESSE-0.012}"
SANS_PAUSE="${SANS_PAUSE-0}"
_ETAPE_COURANTE=0

_attendre_entree() {
  [ "$SANS_PAUSE" = "1" ] && return 0
  # shellcheck disable=SC2162
  read -r -s -n 1 _touche </dev/tty || true
  # q en plein milieu = on sort proprement
  if [ "${_touche-}" = "q" ]; then printf "\n%sDémonstration interrompue.%s\n" "$C_GRIS" "$C_RAZ"; exit 0; fi
}

_taper() {
  local texte="$1" i car
  if [ "$VITESSE" = "0" ]; then printf "%s" "$texte"; return; fi
  i=0
  while [ $i -lt ${#texte} ]; do
    car="${texte:$i:1}"
    printf "%s" "$car"
    sleep "$VITESSE"
    i=$((i + 1))
  done
}

titre() {
  printf "\n%s══════════════════════════════════════════════════════════════════════%s\n" "$C_TITRE" "$C_RAZ"
  printf "%s  %s%s\n" "$C_TITRE" "$1" "$C_RAZ"
  printf "%s══════════════════════════════════════════════════════════════════════%s\n" "$C_TITRE" "$C_RAZ"
  printf "%s  (Entrée pour avancer · q pour sortir)%s\n" "$C_GRIS" "$C_RAZ"
}

etape() {
  _ETAPE_COURANTE="$1"; shift
  printf "\n%s▸ %s. %s%s\n" "$C_ETAPE" "$_ETAPE_COURANTE" "$*" "$C_RAZ"
}

# Ce que l'animateur raconte pendant que ça tourne — affiché en gris, jamais exécuté.
dire() { printf "%s   « %s »%s\n" "$C_DIRE" "$*" "$C_RAZ"; }

# Le pari de prédiction : on pose la question, on attend le vote de la salle.
pari() {
  printf "\n%s   ❓ %s%s\n" "$C_PARI" "$*" "$C_RAZ"
  printf "%s      (on laisse la salle voter — Entrée pour révéler)%s" "$C_GRIS" "$C_RAZ"
  _attendre_entree
  printf "\n"
}

# Affiche la commande comme si on la tapait, attend Entrée, puis l'exécute.
run() {
  printf "\n%s$ %s" "$C_CMD" "$C_RAZ"
  _taper "$*"
  _attendre_entree
  printf "\n"
  eval "$@"
  local code=$?
  if [ $code -ne 0 ]; then printf "%s   (code de sortie %s)%s\n" "$C_GRIS" "$code" "$C_RAZ"; fi
  return 0
}

# Exécute sans rien montrer (préparation, nettoyage).
silence() { eval "$@" >/dev/null 2>&1 || true; }

pause() {
  printf "%s   %s%s" "$C_GRIS" "${1-…}" "$C_RAZ"
  _attendre_entree
  printf "\n"
}

ok() { printf "%s   ✔ %s%s\n" "$C_OK" "$*" "$C_RAZ"; }
ko() { printf "%s   ✘ %s%s\n" "$C_KO" "$*" "$C_RAZ"; }
note() { printf "%s   ℹ %s%s\n" "$C_GRIS" "$*" "$C_RAZ"; }

# Attente active qu'une condition soit vraie (évite les « sleep 30 » au hasard).
attendre_que() {
  local libelle="$1"; shift
  printf "%s   … %s%s" "$C_GRIS" "$libelle" "$C_RAZ"
  local n=0
  SECONDS=0          # variable bash : compte les secondes écoulées
  while [ $n -lt 120 ]; do
    if eval "$@" >/dev/null 2>&1; then
      # Le temps mesuré est la vraie réponse au pari « en combien de secondes ? »
      printf "\r%s   ✔ %-56s%3s s%s\n" "$C_OK" "$libelle" "$SECONDS" "$C_RAZ"
      return 0
    fi
    printf "."
    sleep 1
    n=$((n + 1))
  done
  printf "\r%s   ✘ %-64s%s\n" "$C_KO" "$libelle (délai dépassé)" "$C_RAZ"
  return 1
}

# Vérifie que les outils nécessaires sont là avant de commencer devant la salle.
exiger() {
  local manquants="" outil
  for outil in "$@"; do
    command -v "$outil" >/dev/null 2>&1 || manquants="$manquants $outil"
  done
  if [ -n "$manquants" ]; then
    ko "outil(s) manquant(s) :$manquants"
    exit 1
  fi
}

# Le namespace de travail, surchargeable
NS="${NS-shopix}"
