output "cluster_id" {
  value = scaleway_k8s_cluster.formation.id
}

# Lu par ./setup/10-kapsule-j3.sh, qui l'inscrit lui-même dans l'overlay scaleway.
output "registre" {
  description = "Préfixe d'image à utiliser dans k8s/overlays/scaleway"
  value       = scaleway_registry_namespace.images.endpoint
}

output "kubeconfig" {
  value = abspath("${path.module}/kubeconfig.yaml")
}

output "pour_commencer" {
  value = <<-TXT
    export KUBECONFIG=${abspath(path.module)}/kubeconfig.yaml
    kubectl get nodes
    cd .. && ./setup/10-kapsule-j3.sh      # images, déploiement, observabilité, ArgoCD
  TXT
}

output "rappel" {
  value = <<-TXT
    « terraform destroy » à la fin de la session, sans faute : les nœuds et les
    LoadBalancers sont facturés à l'heure. Deux nœuds DEV1-L ≈ 2,06 €/jour, plus
    0,33 €/jour par LoadBalancer. Le registre public ne coûte rien sous 75 Go.
  TXT
}
