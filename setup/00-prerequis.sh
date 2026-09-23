#!/usr/bin/env bash
# Vérifie que le poste est prêt. À lancer la veille, pas le matin même.
cd "$(dirname "$0")/.." || exit 1
source lib/demo.sh
VITESSE=0

titre "Vérification du poste d'animation"

manquant=0

# ---------------------------------------------------------------- architecture
ARCH=$(uname -m)
OS=$(uname -s)
case "$ARCH" in
  arm64|aarch64)
    ok "processeur ARM ($ARCH) — Apple Silicon"
    note "les images construites ici sont arm64 : parfait pour Minikube local,"
    note "mais illisibles par un cluster Scaleway (amd64) → voir ./setup/02b-images-multiarch.sh"
    ;;
  x86_64|amd64)
    ok "processeur Intel/AMD ($ARCH)"
    ;;
  *) note "architecture inhabituelle : $ARCH" ;;
esac

# ---------------------------------------------------------------- outils
for outil in docker minikube kubectl helm; do
  if command -v "$outil" >/dev/null 2>&1; then
    v=$($outil version --short 2>/dev/null | head -1 || $outil version --client 2>/dev/null | head -1 || $outil --version 2>/dev/null | head -1)
    ok "$outil — ${v:-présent}"
  else
    ko "$outil absent"; manquant=1
  fi
done
for option in k9s jq watch; do
  command -v "$option" >/dev/null 2>&1 && ok "$option (confort)" || note "$option absent — confortable, pas indispensable"
done

# ---------------------------------------------------------------- démon Docker
if docker info >/dev/null 2>&1; then
  ok "le démon Docker répond"

  # mémoire allouée à la machine virtuelle Docker (Docker Desktop sur Mac)
  mem_octets=$(docker info --format '{{.MemTotal}}' 2>/dev/null)
  if [ -n "$mem_octets" ] && [ "$mem_octets" -gt 0 ] 2>/dev/null; then
    mem_go=$((mem_octets / 1073741824))
    if [ "$mem_go" -ge 8 ]; then
      ok "mémoire disponible pour les containers : ${mem_go} Go"
    else
      ko "seulement ${mem_go} Go alloués à Docker — le cluster en demande 6"
      echo "     Docker Desktop → Settings → Resources → Memory : montez à 10 Go"
      manquant=1
    fi
  fi

  # buildx : nécessaire seulement pour le multi-architecture (Scaleway)
  if docker buildx version >/dev/null 2>&1; then
    ok "docker buildx — construction multi-architecture possible"
  else
    note "docker buildx absent — build local possible, mais pas d'image pour Scaleway"
  fi
else
  ko "Docker ne répond pas — lancez Docker Desktop et attendez la baleine verte"
  manquant=1
fi

# ---------------------------------------------------------------- disque
if [ "$OS" = "Darwin" ]; then
  libre=$(df -g / 2>/dev/null | awk 'NR==2{print $4}')
else
  libre=$(df -BG / 2>/dev/null | awk 'NR==2{gsub("G","",$4); print $4}')
fi
if [ -n "$libre" ]; then
  if [ "$libre" -ge 20 ] 2>/dev/null; then ok "espace disque libre : ${libre} Go"
  else ko "seulement ${libre} Go libres — prévoir 20 Go (images + cluster)"; fi
fi

echo
if [ "$manquant" = "1" ]; then
  ko "Poste incomplet — corrigez avant d'aller plus loin."
  echo "   macOS :  brew install minikube kubernetes-cli helm k9s jq"
  exit 1
fi
ok "Poste prêt. Enchaînez avec ./setup/01-cluster-up.sh"
