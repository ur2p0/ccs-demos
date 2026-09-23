# Cluster Kubernetes managé Scaleway (Kapsule) pour la formation CCS.
# Il se crée et se détruit en une commande : on ne paie pas un cluster qui dort.
#
#   terraform init
#   terraform apply                       → ~5 minutes
#   export KUBECONFIG=$PWD/kubeconfig.yaml
#   terraform destroy                     → tout est rendu

terraform {
  required_version = ">= 1.6"
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.50"
    }
  }
}

provider "scaleway" {
  # Renseignez SCW_ACCESS_KEY / SCW_SECRET_KEY / SCW_DEFAULT_PROJECT_ID
  # dans l'environnement, ou ~/.config/scw/config.yaml
  zone   = var.zone
  region = var.region
}

resource "scaleway_vpc_private_network" "formation" {
  name = "${var.nom}-reseau"
}

resource "scaleway_k8s_cluster" "formation" {
  name                        = var.nom
  description                 = "Cluster éphémère — formation CCS ${var.session}"
  version                     = var.version_k8s
  cni                         = "cilium" # Network Policies appliquées, et eBPF pour le discours du Module 8
  private_network_id          = scaleway_vpc_private_network.formation.id
  delete_additional_resources = true # le destroy emporte aussi les LoadBalancers et les disques
  tags                        = ["formation", "ccs", var.session]

  autoscaler_config {
    disable_scale_down = true
  }
}

resource "scaleway_k8s_pool" "noeuds" {
  cluster_id  = scaleway_k8s_cluster.formation.id
  name        = "${var.nom}-noeuds"
  node_type   = var.type_noeud
  size        = var.nombre_noeuds
  autohealing = true
  autoscaling = false
  tags        = ["formation", "ccs"]
}

# kubeconfig écrit à côté du code — pensez à ne jamais le committer.
resource "local_file" "kubeconfig" {
  content         = scaleway_k8s_cluster.formation.kubeconfig[0].config_file
  filename        = "${path.module}/kubeconfig.yaml"
  file_permission = "0600"
}
