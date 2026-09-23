# Cluster Scaleway — optionnel

Les démonstrations tournent sur Minikube. Ce dossier sert à monter un **vrai** cluster
managé quand on veut montrer ce que le local ne sait pas faire :

| Ce que le local ne montre pas | Ce que Kapsule montre |
|---|---|
| Un Service `LoadBalancer` avec une IP publique | Une IP publique attribuée en 30 secondes, et facturée |
| Un disque qui suit le Pod d'un nœud à l'autre | Un volume réseau détaché/rattaché, visible dans la console |
| La console d'un fournisseur | Le PVC qui apparaît comme un disque dans l'interface Scaleway |
| Le coût | La ligne de facturation qui commence à courir |

## Usage

```bash
export SCW_ACCESS_KEY=…  SCW_SECRET_KEY=…  SCW_DEFAULT_PROJECT_ID=…
terraform init
terraform apply                       # ~5 min
export KUBECONFIG=$PWD/kubeconfig.yaml
kubectl apply -k ../k8s/overlays/scaleway
…
terraform destroy                     # à la fin de la session, sans faute
```

L'overlay `scaleway` retire le `nodeSelector` du service de commandes (le disque réseau
suit le Pod) et bascule le front en `LoadBalancer`.
