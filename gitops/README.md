# GitOps — le dépôt comme source de vérité

`apps/shopix.yaml` déclare à ArgoCD où trouver l'état désiré de Shopix : ce dépôt,
dossier `k8s/overlays/minikube`.

## Mise en route (une seule fois, la veille du J3)

```bash
./setup/05-argocd.sh          # installe ArgoCD
./setup/05b-depot-gitops.sh   # dépôt, push, Application ArgoCD
./setup/06b-autotest-j3.sh    # vérifie
```

Le second script fait tout, **sans argument** : il lit le propriétaire du dépôt
depuis la CLI GitHub (`gh api user`), cible le dépôt `ccs-demos` de ce compte, fait
le `git init` si besoin, crée le dépôt sur GitHub s'il n'existe pas encore,
inscrit l'URL dans `apps/shopix.yaml`, committe, pousse la branche `main`,
applique l'`Application` et attend le passage en *Synced / Healthy*.

Variantes :

```bash
DEPOT=autre-nom ./setup/05b-depot-gitops.sh                  # autre nom de dépôt
./setup/05b-depot-gitops.sh https://gitlab.com/moi/x.git     # autre hébergeur
VISIBILITE=private ./setup/05b-depot-gitops.sh               # dépôt privé
```

Si le dépôt distant contient déjà un commit (README créé depuis l'interface web),
le script récupère et rebase cet historique avant de pousser — pas de refus de
push à gérer à la main.

### Si le push échoue

`gh auth status` pour vérifier l'authentification. GitHub n'accepte plus le mot de
passe de compte : `gh auth login`, ou un jeton d'accès personnel de portée `repo`
utilisé à la place du mot de passe.

## Dépôt public : ce qu'il contient

`k8s/base/secret.yaml` porte une clé de paiement **fictive**
(`sk_test_shopix_4242_ne_pas_utiliser`). C'est volontaire, et c'est même une
accroche du Module 8 : un Secret dans Git, c'est du base64, pas du chiffrement.
En revanche, ne remplacez jamais cette valeur par une vraie avant de pousser.

Si vous préférez un dépôt privé, il faut déclarer les identifiants à ArgoCD
(`argocd repo add … --username … --password …`, ou un Secret de type
`repository` dans le namespace `argocd`). C'est une étape de plus la veille.

## Ce que ça change pour la démonstration du J3

- `selfHeal: true` → un `kubectl scale` manuel est annulé en quelques secondes.
- `prune: true` → supprimer un fichier du dépôt supprime l'objet du cluster.
  Seuls les objets créés par ArgoCD sont concernés : les objets posés à la main
  pendant les démonstrations du J2 ne risquent rien.
- Le retour arrière s'appelle `git revert`, et il est revu comme n'importe quel code.

ArgoCD scrute le dépôt **toutes les 3 minutes**. Pendant la démonstration, le
bouton *Refresh* de l'interface évite d'attendre devant la salle.

## À ne pas faire

**N'installez pas ArgoCD avant le J2.** Avec `selfHeal` actif, il annulerait le
« scale à 10 » de la démo 4 et la bascule PSA de la démo 8 pendant qu'elles se
déroulent. La veille du J3, donc — pas avant.

## Sans réseau en salle

ArgoCD doit joindre GitHub. Si la salle est coupée du monde, deux options :
partager la connexion du téléphone le temps de la démonstration (ArgoCD ne
télécharge que quelques kilo-octets), ou héberger un Gitea dans le cluster et y
pousser le dépôt la veille — `repoURL` devient alors une adresse interne du type
`http://gitea.gitea.svc:3000/formation/ccs-demos.git`.
