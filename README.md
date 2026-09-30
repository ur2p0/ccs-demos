# Containers, Kubernetes, GitOps — les démonstrations

Tout ce qui a été manipulé en direct pendant les trois jours de formation, pour le refaire chez vous :
l'application fil rouge **Shopix**, le cluster qui l'héberge, et treize démonstrations guidées.

👉 **Le guide pas à pas, avec les schémas : [`docs/DEMOS.md`](docs/DEMOS.md)**. Pour chaque démonstration :
ce qu'elle montre, ce qui est déployé, chaque commande, la question à se poser avant de la lancer, ce que
vous devez voir et pourquoi.

![Où tournent les démos](docs/schemas/00-vue-ensemble.png)

## Les treize démonstrations

| # | Jour | Démonstration | Script | Il faut |
|---|---|---|---|---|
| 1 | 1 | On containerise Shopix | `demos/j1-01-containers.sh` | Docker |
| 2 | 1 | Le paysage, puis un cluster | `demos/j1-02-premier-cluster.sh` | cluster local |
| 3 | 1 | Le cerveau en action (boucle de réconciliation) | `demos/j1-03-control-plane.sh` | cluster local |
| 4 | 1 | 3 réplicas, puis 10 · Job | `demos/j1-04-objets-calcul.sh` | cluster local |
| 5 | 2 | OOMKilled, taints, anti-affinité, sondes | `demos/j2-01-placement-sante.sh` | cluster local |
| 6 | 2 | Services, DNS, Ingress, Network Policies | `demos/j2-02-reseau.sh` | cluster local |
| 7 | 2 | La donnée qui survit au Pod (PVC) | `demos/j2-03-stockage.sh` | cluster local |
| 8 | 2 | RBAC, Pod Security, Secrets | `demos/j2-04-securite.sh` | cluster local |
| 9 | 3 | La chasse au coupable (Prometheus, Loki, Grafana) | `demos/j3-01-observabilite.sh` | pile du jour 3 |
| 10 | 3 | GitOps en action (ArgoCD) | `demos/j3-02-gitops.sh` | pile du jour 3 + votre fork |
| 11 | 3 | Shopix chez un fournisseur (load balancer, disque réseau, plan de contrôle managé) | `demos/j3-00-manage.sh` | cluster Kapsule (option) |
| 12 | 3 | Vos règles, en YAML : la politique comme code (Kyverno) | `demos/j3-03-kyverno.sh` | un cluster + Helm (Kyverno installé par le script) |
| 13 | 3 | L'alarme : la détection à l'exécution (Falco) | `demos/j3-04-falco.sh` | Kapsule de préférence + Helm (Falco installé par le script) |

Le guide se termine par six manipulations sans script : DaemonSet, StatefulSet, HPA, ConfigMap,
rolling update et rollback, ResourceQuota.

## 1. Ce qu'il vous faut

| | Jours 1 et 2 | Jour 3 en local |
|---|---|---|
| Mémoire allouée à Docker | 8 Go | 10 Go |
| Processeurs | 4 | 4 |

Outils : [Docker](https://docs.docker.com/get-docker/) (Docker Desktop sur macOS et Windows),
[minikube](https://minikube.sigs.k8s.io/docs/start/), [kubectl](https://kubernetes.io/docs/tasks/tools/),
[Helm](https://helm.sh/docs/intro/install/), `git`. Pour le jour 3 : la CLI GitHub [`gh`](https://cli.github.com/).
En confort : [k9s](https://k9scli.io/), `jq`, `watch`.

Sur macOS avec Homebrew : `brew install minikube kubectl helm gh k9s jq`.

**Systèmes testés.** macOS sur Apple Silicon (le poste de la formation). Linux doit fonctionner tel quel.
Windows : passez par WSL2 avec Docker Desktop, sans garantie — les scripts sont en bash.

```bash
./setup/00-prerequis.sh     # vérifie les outils, l'architecture et la mémoire de Docker
```

## 2. Monter l'environnement (jours 1 et 2)

```bash
git clone https://github.com/ur2p0/ccs-demos.git && cd ccs-demos
./setup/01-cluster-up.sh    # Minikube 2 nœuds, Calico, Traefik  (~5 min)
./setup/02-images.sh        # construit Shopix et la charge dans le cluster
./setup/03-deployer.sh      # Shopix tourne
./setup/06-autotest.sh      # rejoue les scénarios et vérifie ~30 points (6-8 min)
```

> Pour le jour 3, **forkez** le dépôt plutôt que de le cloner (bouton *Fork* sur GitHub, en gardant le nom
> `ccs-demos`), puis clonez votre fork : la démonstration GitOps pousse des commits dans votre dépôt.

**Ouvrir la boutique dans le navigateur**

- **macOS** : l'IP du nœud Minikube n'est pas joignable depuis le Mac. Une fois pour toutes :
  `echo '127.0.0.1 shopix.local' | sudo tee -a /etc/hosts`, puis dans un terminal dédié
  `./setup/07-acces.sh` (tunnel vers Traefik) → **http://shopix.local:8888**
- **Linux** : `echo "$(minikube -p ccs ip) shopix.local" | sudo tee -a /etc/hosts` → **http://shopix.local:30080**

## 3. Rejouer une démonstration

```bash
./demos/j1-03-control-plane.sh     # Entrée pour avancer, q pour sortir
VITESSE=0 ./demos/…                # sans l'effet machine à écrire
SANS_PAUSE=1 ./demos/…             # tout d'un trait
./demos/reset.sh --tout            # remet l'environnement dans l'état de départ
```

Chaque script affiche la commande avant de l'exécuter, pose une question (❓) avant les étapes
importantes : faites votre pronostic avant d'appuyer sur Entrée. Les scripts font leur propre
« table rase » au démarrage : on peut les relancer autant de fois qu'on veut.

Le cluster se met en pause et se réveille sans rien perdre :

```bash
./setup/99-cluster-down.sh              # arrête (minikube stop)
minikube start -p ccs                   # redémarre, ~2 min
./setup/99-cluster-down.sh --supprimer  # efface tout
```

## 4. Jour 3 — observabilité et GitOps

### En local (recommandé)

Montez d'abord la mémoire de Docker à 10 Go (Docker Desktop → Settings → Resources), puis :

```bash
./setup/04-observabilite.sh         # Prometheus, Loki, Grafana (~5 min)
./setup/05-argocd.sh                # ArgoCD
gh auth login                       # une fois
./setup/05b-depot-gitops.sh         # relie ArgoCD à VOTRE fork de ccs-demos
kubectl apply -f k8s/demos/10-charge.yaml   # générateur de trafic, à lancer 30 min avant la démo 9
./setup/06b-autotest-j3.sh          # vérifie la pile
./setup/08-acces-j3.sh              # terminal dédié : Grafana :3000, ArgoCD :8080
```

- Grafana : http://localhost:3000 — `admin` / `shopix`
- ArgoCD : http://localhost:8080 — `admin` / mot de passe :
  `kubectl -n argocd get secret argocd-initial-admin-secret -o go-template='{{.data.password | base64decode}}'`

`05b-depot-gitops.sh` lit votre compte GitHub (`gh api user`), vise le dépôt `ccs-demos` de ce compte,
y pousse l'état courant et déclare l'application dans ArgoCD. Après la démo 10, revenez à l'état initial
par Git : `git revert --no-edit HEAD && git push`.

### Option : sur un cluster managé Scaleway Kapsule

Plus fidèle à la production (LoadBalancer public, disques réseau), mais **payant** : environ 2,40 € par
jour pour deux nœuds DEV1-L et un LoadBalancer. Il vous faut un compte Scaleway et ses clés d'API.

```bash
export SCW_ACCESS_KEY=…  SCW_SECRET_KEY=…  SCW_DEFAULT_PROJECT_ID=…
cd terraform && terraform init
terraform apply -var registre=ccs-shopix-<votre-pseudo>   # le nom du registre est unique sur tout Scaleway
cd .. && ./setup/10-kapsule-j3.sh                          # image amd64, Shopix, pile J3, autotest (~20 min)
```

La démonstration 11 (`./demos/j3-00-manage.sh`) montre alors ce que le fournisseur fait de vos manifestes : plan de contrôle opéré, load balancer commandé par un Service, disque réseau qui suit le Pod d'un nœud à l'autre.

Détails dans [`terraform/README.md`](terraform/README.md). **Et à la fin, sans faute :**
`cd terraform && terraform destroy` — un cluster oublié trois semaines coûte une cinquantaine d'euros.

## 5. Quand ça ne marche pas

| Symptôme | Cause probable | Geste |
|---|---|---|
| `ErrImagePull` / `ImagePullBackOff` sur Minikube | l'image n'est pas dans le cluster | `./setup/02-images.sh` |
| Tous les Pods `Pending` | pas assez de mémoire | augmenter la mémoire de Docker, puis recréer le cluster : `./setup/99-cluster-down.sh --supprimer && MEMOIRE=8g ./setup/01-cluster-up.sh` |
| `shopix.local` ne répond pas (macOS) | tunnel non lancé | `./setup/07-acces.sh` dans un terminal dédié |
| Les Network Policies ne bloquent rien | CNI sans Calico | recréer le cluster avec `01-cluster-up.sh` |
| Un Pod reste `Pending` après la démo 5 | un taint est resté posé | `./demos/reset.sh --j2` |
| `kubectl top` ne répond pas | metrics-server absent | `minikube -p ccs addons enable metrics-server` |
| `exec format error` sur Kapsule | image arm64 sur des nœuds x86_64 | passer par `10-kapsule-j3.sh`, qui construit en amd64 |
| « mauvais cluster : ce script attend minikube » | `KUBECONFIG` pointe sur Kapsule | `unset KUBECONFIG && kubectl config use-context ccs` |
| `permission denied: ./setup/…` | bit d'exécution perdu | `chmod +x setup/*.sh demos/*.sh` |

## 6. Ce qu'il y a dans ce dépôt

| Dossier | Contenu |
|---|---|
| `shopix/` | l'application fil rouge : front, API, worker — Node, sans aucune dépendance |
| `k8s/base/` | les manifestes de Shopix (Deployments, Services, ConfigMap, Secret, PVC, Ingress) |
| `k8s/overlays/` | `minikube` et `scaleway` : le même Shopix, deux environnements (Kustomize) |
| `k8s/demos/` | les objets créés ponctuellement pendant une démonstration |
| `k8s/observabilite/` | ServiceMonitor, source Loki, tableau de bord Grafana |
| `demos/` | les treize scripts guidés, plus `reset.sh` |
| `setup/` | préparation, vérification et arrêt de l'environnement |
| `lib/demo.sh` | la mécanique des scripts (affichage, pauses, questions) |
| `terraform/` | le cluster Scaleway Kapsule, à créer et détruire à la demande |
| `gitops/` | ce qu'ArgoCD lit pour la démonstration GitOps |
| `docs/` | le guide des démonstrations et ses schémas |

## 7. Shopix en deux mots

Une boutique en ligne écrite pour la formation, avec des points de rupture volontaires : elle sait fuir en
mémoire (`/leak`), tomber malade sur commande (`/admin/casser?cible=ready|live`, `/admin/reparer`), ramer une
fois sur cent (`/api/paiement`), et elle affiche toujours **quel Pod a répondu**, sur quel nœud (`/whoami`).

Deux déploiements de la même image portent la leçon du stockage : `shopix-api`, sans volume (les commandes
disparaissent avec le Pod), et `shopix-commandes`, avec volume (elles survivent).

## 8. Sécurité

- `k8s/base/secret.yaml` contient une clé de paiement **fictive**. Ne mettez jamais de vraie valeur dans un
  dépôt, même privé.
- Le `kubeconfig` et l'état Terraform (`terraform/kubeconfig.yaml`, `*.tfstate`) donnent les pleins droits sur
  le cluster : ils sont exclus par le `.gitignore`, ne les committez pas.

## Licence

- **Code** (scripts, application, manifestes, Terraform) : [MIT](LICENSE).
- **Contenus pédagogiques** (`docs/`, schémas, ce README) : [CC BY-NC-SA 4.0](LICENSE-DOCS.md) — réutilisation
  libre hors usage commercial, avec attribution et partage dans les mêmes conditions.

© 2026 OnURSide
