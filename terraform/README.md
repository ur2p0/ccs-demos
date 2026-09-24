# Cluster Scaleway Kapsule — les démonstrations du J3

**Ce n'est plus optionnel.** Les démonstrations 9 (observabilité) et 10 (GitOps) tournent
ici, pas sur Minikube : Prometheus, Grafana, Loki et ArgoCD réclament environ 4 Go de RAM
au cluster, ce qu'un Mac portable ne tient pas en plus des deux nœuds et de Shopix.

Le J1 et le J2 restent sur Minikube, en local. Deux clusters coexistent donc pendant la
session, et les scripts le savent : ceux du J1/J2 refusent de tourner ailleurs que sur
Minikube, ceux du J3 annoncent à quel cluster ils parlent.

## Ce que ce Terraform crée

| Ressource | Pourquoi |
|---|---|
| `scaleway_k8s_cluster` | le cluster, CNI **cilium** (Network Policies appliquées, eBPF pour le Module 8) |
| `scaleway_k8s_pool` | 2 nœuds — les démonstrations de placement en ont besoin |
| `scaleway_vpc_private_network` | réseau privé du cluster |
| `scaleway_registry_namespace` | le registre d'images, **public** : pas de secret de tirage à configurer, et gratuit sous 75 Go |
| `local_file` | le `kubeconfig`, écrit à côté du code — jamais committé (`.gitignore`) |

`delete_additional_resources = true` : le `destroy` emporte aussi les LoadBalancers et les
disques créés par le cluster. C'est ce qui évite de payer un volume oublié.

## Usage

```bash
export SCW_ACCESS_KEY=…  SCW_SECRET_KEY=…  SCW_DEFAULT_PROJECT_ID=…

terraform init
terraform apply                    # ~5 min
cd .. && ./setup/10-kapsule-j3.sh  # images, Shopix, observabilité, ArgoCD, autotest

# … et à la fin de la session, sans faute :
cd terraform && terraform destroy
```

## À vérifier avant chaque session

Les gabarits et les versions évoluent, et Kapsule refuse ce qu'il ne propose plus.

Pour les versions de Kubernetes, la commande existe :

```bash
scw k8s version list
```

Pour les gabarits de nœuds, **il n'y a pas de `scw k8s node-type list`** : un node type de
pool est un gabarit d'instance. Essayez :

```bash
scw instance server-type list zone=fr-par-1
```

Si cette forme n'existe pas dans votre version de la CLI, la liste de référence est
l'écran de création de pool dans la console Kapsule. Et dans tous les cas,
`terraform apply` échoue en quelques secondes avec un message explicite si le gabarit
n'est pas disponible dans la zone — c'est un test suffisant, et gratuit.

Si le gabarit n'est plus proposé : `terraform apply -var type_noeud=PLAY2-MICRO` (ou
`PRO2-XXS`, `POP2-2C-8G`, `GP1-XS`). Il faut **8 Go de RAM par nœud** pour la pile du J3.

### Version de Kubernetes : mineure ou complète, pas les deux

L'API Kapsule n'accepte une version **mineure** (`1.34`) que si la mise à niveau
automatique est activée. Sinon elle exige le **patch exact** (`1.34.3`) :

```
Error: minor version x.y must only be used with auto upgrade enabled
```

Le Terraform active donc l'auto-upgrade (`var.auto_maj = true`) avec une fenêtre de
maintenance **le dimanche à 3 h UTC** — aucune journée de formation ne tombe là, et
l'auto-upgrade ne fait que des patches à l'intérieur de `1.34`, jamais un saut de mineure.

Si vous préférez figer le patch : `-var auto_maj=false -var version_k8s=1.34.3`, le numéro
exact venant de `scw k8s version list`.

### Le message « Multiple variable sources detected »

C'est un avertissement, pas une erreur : vos clés existent à la fois dans
`~/.config/scw/config.yaml` et dans l'environnement, et les variables d'environnement
gagnent. Pour le faire taire, choisissez un seul canal — soit `unset SCW_ACCESS_KEY
SCW_SECRET_KEY SCW_DEFAULT_PROJECT_ID` pour utiliser le profil, soit
`scw config unset` pour ne garder que l'environnement. Attention : `10-kapsule-j3.sh` a
besoin de `SCW_SECRET_KEY` **dans l'environnement** pour se connecter au registre.

Si l'apply échoue sur un conflit de nom de registre, c'est que `ccs-shopix` est déjà pris
par quelqu'un d'autre : les namespaces de registre sont uniques pour tout Scaleway.
`terraform apply -var registre=ccs-shopix-<suffixe>` — `10-kapsule-j3.sh` lit la sortie
Terraform et reporte le nom dans l'overlay tout seul.

## Coût

Tarifs relevés en septembre 2026, hors stockage :

| Poste | Prix |
|---|---|
| Plan de contrôle Kapsule | gratuit |
| 2 nœuds `DEV1-L` (4 vCPU / 8 Go) | 0,08568 €/h — **~2,06 €/jour** |
| LoadBalancer (celui du front) | ~0,33 €/jour |
| Registre public sous 75 Go | gratuit |
| Disque `shopix-commandes` (5 Gi) | quelques centimes par jour |

Une répétition de deux heures coûte moins de 50 centimes. Un cluster oublié pendant trois
semaines coûte 50 €. D'où le `destroy`.

## Ce que Kapsule montre et que le local ne montre pas

| Le local ne montre pas | Kapsule montre |
|---|---|
| Un Service `LoadBalancer` avec une IP publique | Une IP publique attribuée en 30 secondes, et facturée |
| Un disque qui suit le Pod d'un nœud à l'autre | Un volume réseau détaché puis rattaché (l'overlay retire le `nodeSelector`) |
| La console d'un fournisseur | Le PVC comme un disque, le LB comme une ressource facturée |
| Le coût | La ligne de facturation qui court |
