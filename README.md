# Démonstrations CCS — Containers, Kubernetes, GitOps

Tout ce qui se manipule en direct pendant les trois jours de formation :
l'application fil rouge **Shopix**, le cluster qui l'héberge, et les dix scripts de
démonstration.

👉 **Le mode d'emploi, c'est [`RUNBOOK.md`](RUNBOOK.md)** — quelle démonstration à quel
créneau, ce qu'on dit, ce qui doit apparaître, et le plan B.

## Démarrage rapide

```bash
./setup/00-prerequis.sh     # le poste est-il prêt ?
./setup/01-cluster-up.sh    # cluster Minikube 2 nœuds + Calico + Traefik
./setup/02-images.sh        # construit Shopix et la charge dans le cluster
./setup/03-deployer.sh      # Shopix tourne
./setup/07-acces.sh         # (macOS) tunnel vers Traefik, terminal dédié

./demos/j1-01-containers.sh # première démonstration
```

Sur macOS, l'IP du nœud Minikube n'est pas routable depuis le Mac : `07-acces.sh`
ouvre un tunnel vers Traefik (donc via l'Ingress) et la boutique répond sur
**http://shopix.local:8888**. Sur Linux, l'IP du nœud suffit, port 30080.

Puis **la vérification qui compte** :

```bash
./setup/06-autotest.sh      # rejoue les 10 démos et vérifie ~30 assertions (6-8 min)
```

Pour le J3 uniquement : `./setup/04-observabilite.sh` et `./setup/05-argocd.sh`.

## Apple Silicon et architectures processeur

Le poste d'animation est un Mac M1 (arm64), les nœuds Scaleway sont en x86_64.
C'est sans conséquence en local, et bloquant sur le cloud — d'où deux scripts d'image :

| Pour | Script | Ce qu'il produit |
|---|---|---|
| **Minikube local** | `setup/02-images.sh` | une image **arm64**, chargée directement dans les nœuds (qui tournent sur le même Mac) |
| **Scaleway Kapsule** | `setup/02b-images-multiarch.sh` | un manifeste **amd64 + arm64** poussé dans un registre |

Un manifeste multi-architecture n'existe que dans un registre : Docker ne sait pas le
garder en local. C'est pour ça que le second script exige une destination.

Le symptôme d'un oubli est reconnaissable : le Pod reste en `CrashLoopBackOff` et les
journaux disent `exec format error`. L'autotest vérifie cette correspondance
(« l'image correspond à l'architecture des nœuds »).

## Ce qu'il y a dans ce dossier

| Dossier | Contenu |
|---|---|
| `shopix/` | L'application fil rouge : front, API, worker. Node, sans aucune dépendance. |
| `k8s/base/` | Les manifestes de Shopix (déploiements, services, ConfigMap, Secret, PVC, Ingress) |
| `k8s/overlays/` | `minikube` (par défaut) et `scaleway` (cluster managé, optionnel) |
| `k8s/demos/` | Les objets créés ponctuellement pendant une démonstration |
| `k8s/observabilite/` | ServiceMonitor et tableau de bord Grafana |
| `demos/` | Les dix scripts, un par démonstration, plus `reset.sh` |
| `setup/` | Préparation et arrêt de l'environnement |
| `lib/demo.sh` | La mécanique des scripts (affichage, pauses, paris de prédiction) |
| `terraform/` | Cluster Scaleway Kapsule, à créer et détruire à la demande |
| `gitops/` | Ce qu'ArgoCD lit pour la démonstration GitOps du J3 |

## Shopix en deux mots

Une boutique en ligne écrite pour la formation, avec des points de rupture volontaires :
elle sait fuir en mémoire (`/leak`), tomber malade sur commande
(`/admin/casser?cible=ready|live`), ramer une fois sur cent (`/api/paiement`), et elle
affiche toujours **quel Pod a répondu**, sur quel nœud.

Deux déploiements de la même image portent la leçon du stockage :

- `shopix-api` — sans volume : les commandes disparaissent avec le Pod ;
- `shopix-commandes` — avec volume : elles survivent.

## Conventions

- Les scripts avancent **pas à pas** (Entrée pour continuer, `q` pour sortir).
- `VITESSE=0` retire l'effet machine à écrire, `SANS_PAUSE=1` enchaîne tout (répétition).
- Rien n'est détruit sans le dire : `./demos/reset.sh` remet l'état de départ,
  `./setup/99-cluster-down.sh` arrête le cluster.

## Note sur l'ancien dossier

`03-Démos/demo-containers/` (mai 2026) contenait cinq scripts Docker génériques autour
d'un nginx « Hello ». Il est remplacé par `demos/j1-01-containers.sh`, qui raconte la
même chose avec l'application du fil rouge. Conservé pour mémoire, plus référencé nulle part.
