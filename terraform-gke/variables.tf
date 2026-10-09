variable "projet" {
  # L'IDENTIFIANT du projet GCP (pas son nom) : « gcloud projects list », colonne PROJECT_ID.
  # Si « ccs-formation » était déjà pris, Google a ajouté un suffixe : -var projet=ccs-formation-123456
  description = "Identifiant du projet GCP"
  type        = string
  default     = "ccs-formation"
}

variable "nom" {
  description = "Nom du cluster"
  type        = string
  default     = "ccs-formation"
}

variable "session" {
  description = "Identifiant de session, repris en étiquette (facturation, ménage)"
  type        = string
  default     = "oct26"
}

variable "region" {
  description = "europe-west9 = Paris"
  type        = string
  default     = "europe-west9"
}

variable "zone" {
  type    = string
  default = "europe-west9-a"
}

variable "registre" {
  description = "Nom du dépôt Artifact Registry (unique dans le projet, pas dans tout GCP)"
  type        = string
  default     = "shopix"
}

variable "type_noeud" {
  # 4 vCPU / 16 Go, comme les 4 vCPU des DEV1-L Kapsule : la pile du J3
  # (kube-prometheus-stack, Loki, ArgoCD, Kyverno, Falco) plus les agents système GKE
  # ne tiennent pas confortablement sur des e2-standard-2 (2 vCPU).
  # Les nœuds sont en x86_64 : l'image est construite en amd64 par 10-gke-j3.sh.
  description = "Gabarit des nœuds"
  type        = string
  default     = "e2-standard-4"
}

variable "nombre_noeuds" {
  description = "2 minimum : les démonstrations de placement et de stockage en ont besoin"
  type        = number
  default     = 2
}
