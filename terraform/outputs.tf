output "cluster_id" {
  value = scaleway_k8s_cluster.formation.id
}

output "pour_commencer" {
  value = <<-TXT
    export KUBECONFIG=${abspath(path.module)}/kubeconfig.yaml
    kubectl get nodes
    kubectl label node $(kubectl get nodes -o jsonpath='{.items[0].metadata.name}') stockage=oui
    kubectl label node $(kubectl get nodes -o jsonpath='{.items[1].metadata.name}') zone=paiement
    kubectl apply -k ../k8s/overlays/scaleway
  TXT
}

output "rappel" {
  value = "Pensez à « terraform destroy » à la fin de la session : le cluster et ses LoadBalancers sont facturés à l'heure."
}
