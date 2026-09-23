// Shopix — application fil rouge de la formation CCS
// Un seul fichier, zéro dépendance : ROLE=front sert la boutique, ROLE=api sert l'API.
"use strict";
const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");

const ROLE = process.env.ROLE || "api";
const PORT = Number(process.env.PORT || 8080);
const VERSION = process.env.SHOPIX_VERSION || "1.0.0";
const COULEUR = process.env.SHOPIX_COULEUR || "#18534F"; // pilotable par ConfigMap
const MESSAGE = process.env.SHOPIX_MESSAGE || "Le e-commerce qui tient la charge";
const API_URL = process.env.API_URL || "http://shopix-api:8080";
const DATA_DIR = process.env.DATA_DIR || "/data";
const TAUX_LENTEUR = Number(process.env.TAUX_LENTEUR || 0.01); // l'incident « 1 fois sur 100 »
const PAIEMENT_CLE = process.env.PAIEMENT_CLE || "(aucune clé montée)";

// Identité du Pod — injectée par la Downward API
const POD = process.env.POD_NAME || require("node:os").hostname();
const NOEUD = process.env.NODE_NAME || "(inconnu)";
const NAMESPACE = process.env.POD_NAMESPACE || "(hors cluster)";
const POD_IP = process.env.POD_IP || "(inconnue)";

// --- état interne, pilotable pour les démonstrations ---
const etat = { vivant: true, pret: true, fuite: [], demarre: Date.now() };

// --- métriques Prometheus, à la main (pas de dépendance) ---
const BUCKETS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10];
const compteurs = new Map(); // "route|status" -> n
const histos = new Map(); // route -> {buckets:[], somme, n}

function mesurer(route, status, secondes) {
  const cle = `${route}|${status}`;
  compteurs.set(cle, (compteurs.get(cle) || 0) + 1);
  let h = histos.get(route);
  if (!h) { h = { buckets: new Array(BUCKETS.length).fill(0), somme: 0, n: 0 }; histos.set(route, h); }
  h.n += 1;
  h.somme += secondes;
  for (let i = 0; i < BUCKETS.length; i++) if (secondes <= BUCKETS[i]) h.buckets[i] += 1;
}

function rendreMetriques() {
  const l = [];
  l.push("# HELP shopix_build_info Version et identité du Pod");
  l.push("# TYPE shopix_build_info gauge");
  l.push(`shopix_build_info{version="${VERSION}",role="${ROLE}",pod="${POD}",noeud="${NOEUD}"} 1`);
  l.push("# HELP shopix_requests_total Nombre de requêtes servies");
  l.push("# TYPE shopix_requests_total counter");
  for (const [cle, n] of compteurs) {
    const [route, status] = cle.split("|");
    l.push(`shopix_requests_total{role="${ROLE}",pod="${POD}",route="${route}",status="${status}"} ${n}`);
  }
  l.push("# HELP shopix_request_duration_seconds Temps de réponse");
  l.push("# TYPE shopix_request_duration_seconds histogram");
  for (const [route, h] of histos) {
    const base = `role="${ROLE}",pod="${POD}",route="${route}"`;
    for (let i = 0; i < BUCKETS.length; i++) l.push(`shopix_request_duration_seconds_bucket{${base},le="${BUCKETS[i]}"} ${h.buckets[i]}`);
    l.push(`shopix_request_duration_seconds_bucket{${base},le="+Inf"} ${h.n}`);
    l.push(`shopix_request_duration_seconds_sum{${base}} ${h.somme.toFixed(4)}`);
    l.push(`shopix_request_duration_seconds_count{${base}} ${h.n}`);
  }
  const m = process.memoryUsage();
  l.push("# HELP shopix_memoire_octets Mémoire résidente du processus");
  l.push("# TYPE shopix_memoire_octets gauge");
  l.push(`shopix_memoire_octets{role="${ROLE}",pod="${POD}"} ${m.rss}`);
  l.push("# HELP shopix_commandes_total Commandes enregistrées");
  l.push("# TYPE shopix_commandes_total gauge");
  l.push(`shopix_commandes_total{role="${ROLE}",pod="${POD}"} ${lireCommandes().length}`);
  return l.join("\n") + "\n";
}

// --- catalogue et commandes ---
const CATALOGUE = [
  { ref: "SHX-001", nom: "Casque audio Cabestan", prix: 89.9, stock: 42 },
  { ref: "SHX-002", nom: "Sac à dos Conteneur 30L", prix: 64.0, stock: 17 },
  { ref: "SHX-003", nom: "Montre Timonier", prix: 149.0, stock: 8 },
  { ref: "SHX-004", nom: "Enceinte Quai Nord", prix: 119.5, stock: 0 },
  { ref: "SHX-005", nom: "Lampe Phare", prix: 39.9, stock: 63 },
  { ref: "SHX-006", nom: "Clavier Manifeste", prix: 79.0, stock: 25 },
];

const fichierCommandes = () => path.join(DATA_DIR, "commandes.json");

function lireCommandes() {
  try { return JSON.parse(fs.readFileSync(fichierCommandes(), "utf8")); } catch { return []; }
}

function ecrireCommandes(liste) {
  try {
    fs.mkdirSync(DATA_DIR, { recursive: true });
    fs.writeFileSync(fichierCommandes(), JSON.stringify(liste, null, 1));
    return true;
  } catch (e) {
    journal("erreur", `écriture impossible dans ${DATA_DIR} : ${e.code} — pas de volume monté ?`);
    return false;
  }
}

// --- journalisation structurée, sur stdout (12-Factor) ---
function journal(niveau, message, extra = {}) {
  process.stdout.write(JSON.stringify({ ts: new Date().toISOString(), niveau, role: ROLE, pod: POD, message, ...extra }) + "\n");
}

const dormir = (ms) => new Promise((r) => setTimeout(r, ms));

// --- la boutique (ROLE=front) ---
function page(produits, erreurApi) {
  const cartes = produits.map((p) => `
      <article class="p">
        <div class="v">${p.nom}</div>
        <div class="r">${p.ref}</div>
        <div class="x">${p.prix.toFixed(2)} €</div>
        <div class="s ${p.stock === 0 ? "ko" : ""}">${p.stock === 0 ? "rupture" : p.stock + " en stock"}</div>
      </article>`).join("");
  return `<!doctype html><html lang="fr"><head><meta charset="utf-8">
<title>Shopix</title><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
:root{--v:${COULEUR};--o:#D6955B;--m:#ECF8F6;--g:#64748B}
*{box-sizing:border-box}body{margin:0;font:16px/1.5 system-ui,-apple-system,Segoe UI,sans-serif;color:#1E1E1E;background:#fff}
header{background:var(--v);color:#fff;padding:22px 28px}
h1{margin:0;font-size:28px;letter-spacing:-.5px}h1 span{color:var(--o)}
header p{margin:4px 0 0;opacity:.85;font-size:14px}
.bar{background:var(--m);border-bottom:1px solid #CFE5E0;padding:10px 28px;font-size:13px;color:#0f3f3c;display:flex;flex-wrap:wrap;gap:18px}
.bar b{font-weight:600}
main{padding:24px 28px;display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:14px}
.p{border:1px solid #E2E8F0;border-radius:10px;padding:14px}
.v{font-weight:600;color:var(--v)}.r{font-size:12px;color:var(--g);margin:2px 0 8px}
.x{font-size:20px;font-weight:600}.s{font-size:13px;color:var(--g)}.s.ko{color:#b4532a;font-weight:600}
.err{margin:24px 28px;padding:16px 18px;border:1px solid #D6955B;background:#F4F1EF;border-radius:10px}
.err b{color:#9C6644}
footer{padding:18px 28px;color:var(--g);font-size:12px;border-top:1px solid #E2E8F0;margin-top:20px}
</style></head><body>
<header><h1>Shopix<span>.</span></h1><p>${MESSAGE}</p></header>
<div class="bar">
  <span>servi par <b>${POD}</b></span>
  <span>nœud <b>${NOEUD}</b></span>
  <span>namespace <b>${NAMESPACE}</b></span>
  <span>IP <b>${POD_IP}</b></span>
  <span>version <b>${VERSION}</b></span>
</div>
${erreurApi ? `<div class="err"><b>Catalogue indisponible.</b> Le front n'arrive pas à joindre l'API (${erreurApi}).</div>` : `<main>${cartes}</main>`}
<footer>Application de démonstration de la formation CCS — Containers, Kubernetes, GitOps</footer>
</body></html>`;
}

// --- routage ---
async function router(req, res) {
  const debut = process.hrtime.bigint();
  const url = new URL(req.url, `http://${req.headers.host || "shopix"}`);
  const chemin = url.pathname;
  let route = chemin;
  let status = 200;
  let corps = "";
  let type = "application/json; charset=utf-8";

  try {
    // --- sondes ---
    if (chemin === "/health") {
      status = etat.vivant ? 200 : 500;
      corps = JSON.stringify({ vivant: etat.vivant, pod: POD, uptime_s: Math.round((Date.now() - etat.demarre) / 1000) });
    } else if (chemin === "/ready") {
      status = etat.pret ? 200 : 503;
      corps = JSON.stringify({ pret: etat.pret, pod: POD });
    } else if (chemin === "/metrics") {
      type = "text/plain; version=0.0.4; charset=utf-8";
      corps = rendreMetriques();
    } else if (chemin === "/whoami") {
      corps = JSON.stringify({ role: ROLE, pod: POD, noeud: NOEUD, namespace: NAMESPACE, ip: POD_IP, version: VERSION }, null, 1);

    // --- leviers de démonstration ---
    } else if (chemin === "/admin/casser") {
      const cible = url.searchParams.get("cible") || "ready";
      if (cible === "live") etat.vivant = false; else etat.pret = false;
      journal("alerte", `sonde ${cible} cassée volontairement (démonstration)`);
      corps = JSON.stringify({ casse: cible, vivant: etat.vivant, pret: etat.pret, pod: POD });
    } else if (chemin === "/admin/reparer") {
      etat.vivant = true; etat.pret = true;
      journal("info", "sondes remises en état");
      corps = JSON.stringify({ vivant: true, pret: true, pod: POD });
    } else if (chemin === "/leak") {
      const mo = Number(url.searchParams.get("mo") || 20);
      for (let i = 0; i < mo; i++) etat.fuite.push(Buffer.alloc(1024 * 1024, 1));
      const rss = Math.round(process.memoryUsage().rss / 1048576);
      journal("alerte", `fuite mémoire simulée : +${mo} Mo (rss ${rss} Mo)`, { rss_mo: rss });
      corps = JSON.stringify({ ajoute_mo: mo, total_mo: etat.fuite.length, rss_mo: rss, pod: POD });
    } else if (chemin === "/slow") {
      const ms = Number(url.searchParams.get("ms") || 2000);
      await dormir(ms);
      corps = JSON.stringify({ dormi_ms: ms, pod: POD });

    // --- API métier ---
    } else if (chemin === "/api/produits") {
      corps = JSON.stringify(CATALOGUE);
    } else if (chemin === "/api/commandes" && req.method === "POST") {
      const liste = lireCommandes();
      const commande = { id: "CMD-" + String(liste.length + 1).padStart(4, "0"), ref: url.searchParams.get("ref") || "SHX-001", le: new Date().toISOString(), par: POD, etat: "en attente" };
      liste.push(commande);
      const ok = ecrireCommandes(liste);
      status = ok ? 201 : 507;
      corps = JSON.stringify(ok ? commande : { erreur: "stockage indisponible", indice: `écriture refusée dans ${DATA_DIR}` });
      if (ok) journal("info", `commande ${commande.id} enregistrée`, { commande: commande.id });
    } else if (chemin === "/api/commandes") {
      corps = JSON.stringify(lireCommandes());
    } else if (chemin === "/api/paiement") {
      // L'incident du jour : une requête sur cent part en vrille.
      const malchance = Math.random() < TAUX_LENTEUR;
      if (malchance) {
        journal("alerte", "appel au prestataire de paiement anormalement long", { lent: true });
        await dormir(2000 + Math.random() * 1500);
      } else {
        await dormir(20 + Math.random() * 40);
      }
      corps = JSON.stringify({ paye: true, lent: malchance, cle: PAIEMENT_CLE.slice(0, 6) + "…", pod: POD });

    // --- la boutique ---
    } else if (chemin === "/" && ROLE === "front") {
      type = "text/html; charset=utf-8";
      let produits = [], erreur = null;
      try {
        const r = await fetch(`${API_URL}/api/produits`, { signal: AbortSignal.timeout(2500) });
        if (!r.ok) throw new Error("HTTP " + r.status);
        produits = await r.json();
      } catch (e) {
        erreur = e.name === "TimeoutError" ? "délai dépassé" : e.message;
        journal("erreur", `API injoignable : ${erreur}`, { api: API_URL });
      }
      corps = page(produits, erreur);
      route = "/";
    } else if (chemin === "/") {
      corps = JSON.stringify({ service: "shopix-" + ROLE, version: VERSION, pod: POD, routes: ["/api/produits", "/api/commandes", "/api/paiement", "/health", "/ready", "/metrics", "/whoami"] }, null, 1);
    } else {
      status = 404;
      route = "(inconnue)";
      corps = JSON.stringify({ erreur: "route inconnue", chemin });
    }
  } catch (e) {
    status = 500;
    corps = JSON.stringify({ erreur: e.message });
    journal("erreur", e.message);
  }

  res.writeHead(status, { "content-type": type, "x-shopix-pod": POD, "x-shopix-version": VERSION });
  res.end(corps);

  const secondes = Number(process.hrtime.bigint() - debut) / 1e9;
  mesurer(route, status, secondes);
  if (!["/health", "/ready", "/metrics"].includes(chemin))
    journal("acces", `${req.method} ${chemin} ${status}`, { route, status, duree_ms: Math.round(secondes * 1000) });
}

const serveur = http.createServer(router);
serveur.listen(PORT, () => journal("info", `shopix-${ROLE} ${VERSION} à l'écoute sur ${PORT}`, { noeud: NOEUD, namespace: NAMESPACE }));

// Arrêt propre : on finit les requêtes en cours (le « contrat » du Module 3)
for (const signal of ["SIGTERM", "SIGINT"]) {
  process.on(signal, () => {
    journal("info", `${signal} reçu — arrêt propre, on laisse finir les requêtes en cours`);
    etat.pret = false; // on sort du Service avant de fermer
    setTimeout(() => serveur.close(() => process.exit(0)), 2000);
  });
}
