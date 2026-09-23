#!/usr/bin/env bash
# Ouvre l'accès à la boutique depuis le navigateur du Mac.
#
# Pourquoi ce script existe : avec le driver Docker sur macOS, les containers
# tournent dans une machine virtuelle. L'IP du nœud Minikube (192.168.49.x)
# vit à l'intérieur de cette VM et n'est PAS routable depuis macOS — un NodePort
# ne suffit donc pas. Sur Linux, l'IP du nœud est directement joignable et ce
# script est inutile.
#
# Il maintient un tunnel vers Traefik : le trafic passe donc bien par l'Ingress,
# et la démonstration réseau garde tout son sens.
#
#   ./setup/07-acces.sh          laisse tourner dans un terminal dédié
#   PORT_ACCES=9000 ./setup/07-acces.sh
cd "$(dirname "$0")/.." || exit 1
source lib/demo.sh
VITESSE=0
PORT_ACCES="${PORT_ACCES-8888}"

titre "Accès à la boutique — tunnel vers Traefik"
exiger kubectl

if ! kubectl -n traefik get svc traefik >/dev/null 2>&1; then
  ko "Traefik n'est pas installé — relancez ./setup/01-cluster-up.sh"
  exit 1
fi

# La ligne /etc/hosts doit pointer sur la boucle locale, pas sur l'IP du nœud.
if grep -q "shopix.local" /etc/hosts 2>/dev/null; then
  if grep -qE "^\s*127\.0\.0\.1\s+.*shopix\.local" /etc/hosts 2>/dev/null; then
    ok "/etc/hosts : shopix.local → 127.0.0.1"
  else
    ko "/etc/hosts fait pointer shopix.local ailleurs que sur 127.0.0.1"
    grep "shopix.local" /etc/hosts | sed 's/^/     /'
    echo
    echo "   Corrigez avec :"
    echo "     sudo sed -i '' '/shopix.local/d' /etc/hosts"
    echo "     echo '127.0.0.1 shopix.local' | sudo tee -a /etc/hosts"
    echo
    exit 1
  fi
else
  note "shopix.local absent de /etc/hosts — ajoutez-le une fois pour toutes :"
  echo "     echo '127.0.0.1 shopix.local' | sudo tee -a /etc/hosts"
  echo
  note "sans cette ligne, utilisez http://localhost:$PORT_ACCES"
fi

echo
ok "Boutique : http://shopix.local:$PORT_ACCES"
note "laissez ce terminal ouvert pendant toute la session · Ctrl-C pour arrêter"
note "le tunnel se relance tout seul s'il tombe"
echo

# Boucle de supervision : un port-forward finit toujours par lâcher (veille,
# redéploiement d'un Pod…). On le remonte automatiquement.
while true; do
  kubectl -n traefik port-forward svc/traefik "$PORT_ACCES:80" >/dev/null 2>&1
  code=$?
  [ $code -eq 130 ] && break   # Ctrl-C
  printf "%s   tunnel interrompu — relance…%s\n" "$C_GRIS" "$C_RAZ"
  sleep 2
done
echo
note "tunnel fermé"
