# Le cluster du jour 3 sur Google Cloud (GKE)

L'alternative à `terraform/` (Scaleway Kapsule), avec le même contrat : on le crée le
matin, on le détruit le soir. Les démonstrations 9 à 13 tournent à l'identique ; la
démonstration 11 (« Shopix chez un fournisseur ») détecte GKE et adapte son discours.

| | Kapsule (`terraform/`) | GKE (`terraform-gke/`) |
|---|---|---|
| Plan de contrôle | opéré par Scaleway | opéré par Google — cluster **zonal**, couvert par le crédit gratuit GKE |
| Nœuds | 2 × DEV1-L (4 vCPU / 8 Go) | 2 × e2-standard-4 (4 vCPU / 16 Go) |
| Network Policies | Cilium | Dataplane V2 (Cilium opéré par Google) |
| Registre | Container Registry public | Artifact Registry privé, lu par le compte de service des nœuds |
| Authentification | clés SCW | `gcloud` (aucun secret à exporter) |
| Préparation du J3 | `./setup/10-kapsule-j3.sh` | `./setup/10-gke-j3.sh` |

## Une fois pour toutes

1. **Console Google Cloud** : créer le projet `ccs-formation` et lui **associer un compte
   de facturation**. Notez son *identifiant* (`gcloud projects list`, colonne
   PROJECT_ID) : si `ccs-formation` était pris, Google a ajouté un suffixe.
2. **Sur le Mac** :

```bash
gcloud components install gke-gcloud-auth-plugin   # kubectl en a besoin pour parler à GKE
gcloud auth login                                    # pour gcloud et docker
gcloud config set project ccs-formation              # votre PROJECT_ID
gcloud auth application-default login                # pour Terraform
gcloud auth application-default set-quota-project ccs-formation
```

## Avant chaque session

```bash
cd terraform-gke
terraform init
terraform apply                       # ~8 min ; -var projet=<id> si l'identifiant diffère
cd .. && ./setup/10-gke-j3.sh          # image amd64, Shopix, observabilité, ArgoCD, autotest
export KUBECONFIG="$PWD/terraform-gke/kubeconfig.yaml"
```

**Au premier `apply` d'un projet neuf**, il peut échouer sur un compte de service
`…-compute@developer.gserviceaccount.com` « introuvable » : Google le crée quelques
secondes après l'activation de l'API Compute. Relancez simplement `terraform apply`.

## Et à la fin, sans faute

```bash
./setup/99-gke-down.sh
```

Pas un simple `terraform destroy` : contrairement à Kapsule, GKE ne supprime pas
forcément les load balancers et les disques créés par Kubernetes quand le cluster
disparaît. Le script fait supprimer les namespaces applicatifs d'abord (ArgoCD en
premier, sinon il recrée tout), attend que Services et volumes soient partis, lance
`terraform destroy`, puis vérifie qu'il ne reste ni disque `pvc-…` ni load balancer.

Les API restent activées (c'est voulu), le dépôt Artifact Registry est supprimé avec le
reste. Vérifiez le lendemain dans Facturation → Rapports : les coûts arrivent avec
quelques heures de décalage.

## Quand ça ne marche pas

| Symptôme | Cause probable | Geste |
|---|---|---|
| `Quota 'CPUS' exceeded` | compte en période d'essai (plafond de vCPU) ou quota régional bas | IAM et administration → Quotas : demander 16 vCPU en europe-west9, ou `-var type_noeud=e2-standard-2 -var nombre_noeuds=3` |
| `billing account … is not open` / API non activable | pas de facturation sur le projet | associer un compte de facturation au projet |
| `gke-gcloud-auth-plugin not found` | plugin absent | `gcloud components install gke-gcloud-auth-plugin` |
| Pods en `ImagePullBackOff` | image non poussée, ou droit de lecture absent | relancer `./setup/10-gke-j3.sh` ; vérifier l'IAM du dépôt Artifact Registry |
| « mauvais cluster : ce script attend minikube » | `KUBECONFIG` pointe sur GKE | `unset KUBECONFIG && kubectl config use-context ccs` |
