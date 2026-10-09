# Cluster Kubernetes managé Google (GKE Standard) pour la formation CCS — l'alternative
# à terraform/ (Scaleway Kapsule). Même contrat : il se crée et se détruit en une commande,
# et ses sorties (registre, kubeconfig) sont lues par ./setup/10-gke-j3.sh.
#
#   gcloud auth application-default login     → une fois : Terraform utilise ces identifiants
#   terraform init
#   terraform apply                            → ~8 minutes
#   terraform destroy                          → tout est rendu
#
# Aucun secret à exporter : l'authentification passe par gcloud (ADC). Le kubeconfig
# produit ne contient pas de certificat client — il appelle gke-gcloud-auth-plugin.

terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.4"
    }
  }
}

provider "google" {
  project = var.projet
  region  = var.region
  zone    = var.zone
}

# Lu après l'activation des API (depends_on) : sur un projet neuf, l'API Resource
# Manager peut ne pas être encore active au moment du plan.
data "google_project" "courant" {
  depends_on = [google_project_service.api]
}

# ------------------------------------------------------------------ les API du projet
# Un projet neuf n'a aucune API activée. disable_on_destroy = false : un destroy ne
# désactive pas les API (les réactiver prend plusieurs minutes à la session suivante).
resource "google_project_service" "api" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
  ])
  service            = each.value
  disable_on_destroy = false
}

# ------------------------------------------------------------------ le réseau
# Un VPC dédié plutôt que le réseau « default » : certains projets (organisations
# récentes) n'en ont pas, et c'est l'équivalent du réseau privé du cluster Kapsule.
resource "google_compute_network" "formation" {
  name                    = "${var.nom}-reseau"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.api]
}

resource "google_compute_subnetwork" "formation" {
  name          = "${var.nom}-noeuds"
  network       = google_compute_network.formation.id
  region        = var.region
  ip_cidr_range = "10.10.0.0/20" # les nœuds

  # GKE « VPC-native » : les Pods et les Services ont leurs propres plages, routées
  # par le VPC — c'est le modèle IP-par-Pod du Module 4, sans NAT.
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.20.0.0/16"
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.30.0.0/20"
  }
}

# ------------------------------------------------------------------ le cluster
resource "google_container_cluster" "formation" {
  name        = var.nom
  description = "Cluster éphémère — formation CCS ${var.session}"
  location    = var.zone # cluster ZONAL : un seul plan de contrôle, couvert par le crédit gratuit GKE

  network    = google_compute_network.formation.id
  subnetwork = google_compute_subnetwork.formation.id
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Dataplane V2 = Cilium/eBPF opéré par Google : les NetworkPolicies sont appliquées,
  # comme avec Calico en local et Cilium sur Kapsule. Rien d'autre à installer.
  datapath_provider = "ADVANCED_DATAPATH"

  # On ne précise pas de version : le canal REGULAR fournit une version supportée.
  # C'est ce qui évite l'erreur « version retirée » vécue sur Kapsule.
  release_channel {
    channel = "REGULAR"
  }

  # Mises à jour automatiques la nuit, hors des journées de formation.
  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }

  # On gère nos propres nœuds (pool ci-dessous) : le pool par défaut est supprimé.
  remove_default_node_pool = true
  initial_node_count       = 1

  # Sans ça, « terraform destroy » refuse de supprimer le cluster.
  deletion_protection = false

  resource_labels = {
    formation = "ccs"
    session   = var.session
  }
}

resource "google_container_node_pool" "noeuds" {
  name       = "${var.nom}-noeuds"
  cluster    = google_container_cluster.formation.id
  location   = var.zone
  node_count = var.nombre_noeuds

  management {
    auto_repair  = true # l'équivalent de l'autohealing Kapsule
    auto_upgrade = true
  }

  node_config {
    machine_type = var.type_noeud
    disk_type    = "pd-balanced"
    disk_size_gb = 50
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
    labels       = { formation = "ccs" }
  }
}

# ------------------------------------------------------------------ le registre
resource "google_artifact_registry_repository" "images" {
  location      = var.region
  repository_id = var.registre
  description   = "Images de la formation CCS"
  format        = "DOCKER"
  depends_on    = [google_project_service.api]
}

# Les nœuds tournent avec le compte de service Compute par défaut. Dans les
# organisations récentes, il n'a plus aucun rôle automatiquement : on lui donne
# explicitement le droit de tirer les images, et le rôle minimal d'un nœud GKE.
locals {
  sa_noeuds = "serviceAccount:${data.google_project.courant.number}-compute@developer.gserviceaccount.com"
}

resource "google_artifact_registry_repository_iam_member" "lecture_noeuds" {
  location   = google_artifact_registry_repository.images.location
  repository = google_artifact_registry_repository.images.name
  role       = "roles/artifactregistry.reader"
  member     = local.sa_noeuds
  depends_on = [google_project_service.api]
}

resource "google_project_iam_member" "noeud_gke" {
  project    = var.projet
  role       = "roles/container.defaultNodeServiceAccount"
  member     = local.sa_noeuds
  depends_on = [google_project_service.api]
}

# ------------------------------------------------------------------ le kubeconfig
# Écrit à côté du code, comme pour Kapsule. Il ne contient AUCUN secret : l'accès
# passe par gke-gcloud-auth-plugin et votre session gcloud. Ne le committez pas
# quand même (adresse du cluster).
resource "local_file" "kubeconfig" {
  filename        = "${path.module}/kubeconfig.yaml"
  file_permission = "0600"
  content = yamlencode({
    apiVersion      = "v1"
    kind            = "Config"
    current-context = var.nom
    clusters = [{
      name = var.nom
      cluster = {
        server                     = "https://${google_container_cluster.formation.endpoint}"
        certificate-authority-data = google_container_cluster.formation.master_auth[0].cluster_ca_certificate
      }
    }]
    contexts = [{
      name    = var.nom
      context = { cluster = var.nom, user = var.nom }
    }]
    users = [{
      name = var.nom
      user = {
        exec = {
          apiVersion         = "client.authentication.k8s.io/v1beta1"
          command            = "gke-gcloud-auth-plugin"
          installHint        = "gcloud components install gke-gcloud-auth-plugin"
          provideClusterInfo = true
          interactiveMode    = "IfAvailable"
        }
      }
    }]
  })
  depends_on = [google_container_node_pool.noeuds]
}
