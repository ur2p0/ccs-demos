// Shopix — worker de traitement des commandes.
// MODE=boucle (défaut)  : tourne en continu, traite les commandes en attente → Deployment
// MODE=facturation      : une passe, puis sort en code 0 → Job / CronJob de nuit
"use strict";
const fs = require("node:fs");
const path = require("node:path");

const MODE = process.env.MODE || "boucle";
const DATA_DIR = process.env.DATA_DIR || "/data";
const PAUSE_MS = Number(process.env.PAUSE_MS || 5000);
const POD = process.env.POD_NAME || require("node:os").hostname();

const fichier = (n) => path.join(DATA_DIR, n);

function journal(niveau, message, extra = {}) {
  process.stdout.write(JSON.stringify({ ts: new Date().toISOString(), niveau, role: "worker", mode: MODE, pod: POD, message, ...extra }) + "\n");
}

function lire(nom) {
  try { return JSON.parse(fs.readFileSync(fichier(nom), "utf8")); } catch { return []; }
}

function ecrire(nom, contenu) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  fs.writeFileSync(fichier(nom), JSON.stringify(contenu, null, 1));
}

function traiterUnePasse() {
  const commandes = lire("commandes.json");
  const enAttente = commandes.filter((c) => c.etat === "en attente");
  if (enAttente.length === 0) { journal("info", "rien à traiter"); return 0; }
  for (const c of enAttente) {
    c.etat = "expédiée";
    c.traitee_le = new Date().toISOString();
    c.traitee_par = POD;
    journal("info", `commande ${c.id} expédiée`, { commande: c.id });
  }
  ecrire("commandes.json", commandes);
  return enAttente.length;
}

function facturer() {
  const commandes = lire("commandes.json");
  const expediees = commandes.filter((c) => c.etat === "expédiée");
  const facture = {
    emise_le: new Date().toISOString(),
    emise_par: POD,
    lignes: expediees.length,
    total_estime: Number((expediees.length * 87.4).toFixed(2)),
  };
  ecrire("facture-" + new Date().toISOString().slice(0, 10) + ".json", facture);
  journal("info", `facturation de nuit : ${facture.lignes} ligne(s), ${facture.total_estime} €`, facture);
  return facture.lignes;
}

if (MODE === "facturation") {
  traiterUnePasse();
  facturer();
  journal("info", "travail terminé — le Pod va passer en Completed");
  process.exit(0);
} else {
  journal("info", `worker démarré — une passe toutes les ${PAUSE_MS} ms`);
  setInterval(traiterUnePasse, PAUSE_MS);
  for (const signal of ["SIGTERM", "SIGINT"])
    process.on(signal, () => { journal("info", `${signal} reçu — arrêt propre`); process.exit(0); });
}
