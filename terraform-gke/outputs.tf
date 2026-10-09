output "cluster" {
  value = google_container_cluster.formation.name
}

# Lu par ./setup/10-gke-j3.sh, qui l'inscrit lui-même dans l'overlay gke.
output "registre" {
  description = "Préfixe d'image à utiliser dans k8s/overlays/gke"
  value       = "${var.region}-docker.pkg.dev/${var.projet}/${google_artifact_registry_repository.images.repository_id}"
}

output "kubeconfig" {
  value = abspath("${path.module}/kubeconfig.yaml")
}

output "pour_commencer" {
  value = <<-TXT
    export KUBECONFIG="${abspath(path.module)}/kubeconfig.yaml"
    kubectl get nodes
    cd .. && ./setup/10-gke-j3.sh      # image, déploiement, observabilité, ArgoCD
  TXT
}

output "rappel" {
  value = <<-TXT
    « terraform destroy » à la fin de la session, sans faute : les nœuds, les disques et
    les load balancers sont facturés à l'heure. Vérifiez le coût du jour dans
    Facturation → Rapports (les chiffres arrivent avec quelques heures de décalage).
  TXT
}
