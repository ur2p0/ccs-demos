# ✅ Shopix — image de production
# Trois principes : une base minimale, le cache des dépendances séparé du code,
# et un processus qui ne tourne pas en root.

# ---- étape 1 : les dépendances (change rarement → cache très stable) ----
FROM node:24-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
# Shopix n'a volontairement aucune dépendance externe (elle doit pouvoir se
# construire sans réseau, en salle). npm ne crée donc pas node_modules : on le
# crée nous-mêmes pour que l'étape suivante puisse le recopier, et surtout pour
# garder la structure de couches qu'on veut montrer.
RUN npm ci --omit=dev --no-audit --no-fund && npm cache clean --force && mkdir -p /app/node_modules

# ---- étape 2 : l'image finale (ne contient ni le cache npm, ni les outils de build) ----
FROM node:24-alpine
ENV NODE_ENV=production
WORKDIR /app

# node:alpine fournit déjà un utilisateur non privilégié « node » (uid 1000)
COPY --from=deps --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node package.json ./
COPY --chown=node:node src ./src
COPY --chown=node:node worker ./worker

# Le répertoire de données. Pas de VOLUME déclaré ici : sans cela, Docker
# créerait un volume anonyme à chaque « docker run », et la démonstration
# « un container ne retient rien » deviendrait fausse.
RUN mkdir -p /data && chown node:node /data

USER node
EXPOSE 8080

# Le moteur sait vérifier lui-même que l'application répond
HEALTHCHECK --interval=10s --timeout=2s --start-period=5s --retries=3 \
  CMD wget -q -O- http://127.0.0.1:8080/health || exit 1

# Forme « exec » : node est le PID 1 et reçoit SIGTERM directement
CMD ["node", "src/server.js"]
