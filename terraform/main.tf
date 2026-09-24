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

  # Contrainte de l'API Kapsule : une version MINEURE (« 1.34 ») n'est acceptée que si
  # la mise à niveau automatique est activée. Sinon il faut le patch exact (« 1.34.3 »),
  # qu'il faudrait aller relever avant chaque session — c'est précisément ce qu'on ne
  # veut pas avoir à faire. Message en clair si on se trompe :
  #   Error: minor version x.y must only be used with auto upgrade enabled
  #
  # La fenêtre de maintenance est placée le dimanche à 3 h UTC : aucune journée de
  # formation ne tombe là. Et l'auto-upgrade ne fait que des patches à l'intérieur de
  # 1.34 — jamais un saut de version mineure.
  auto_upgrade {
    enable                        = var.auto_maj
    maintenance_window_start_hour = var.fenetre_heure
    maintenance_window_day        = var.fenetre_jour
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

# Le registre d'images. PUBLIC volontairement : un namespace public dispense de
# configurer un secret de tirage dans le cluster (Kapsule tire sans authentification),
# et le palier gratuit va jusqu'à 75 Go — l'image Shopix pèse 240 Mo par architecture.
# ⚠️ Le nom d'un namespace de registre est unique pour TOUT Scaleway : si l'apply
# échoue sur un conflit de nom, changez var.registre.
resource "scaleway_registry_namespace" "images" {
  name        = var.registre
  description = "Images de la formation CCS — public, aucun secret de tirage nécessaire"
  is_public   = true
  region      = var.region
}

# kubeconfig écrit à côté du code — pensez à ne jamais le committer.
resource "local_file" "kubeconfig" {
  content         = scaleway_k8s_cluster.formation.kubeconfig[0].config_file
  filename        = "${path.module}/kubeconfig.yaml"
  file_permission = "0600"
}
