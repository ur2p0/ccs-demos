variable "nom" {
  description = "Nom du cluster"
  type        = string
  default     = "ccs-formation"
}

variable "session" {
  description = "Identifiant de session, repris en étiquette (facturation, ménage)"
  type        = string
  default     = "sept26"
}

variable "region" {
  type    = string
  default = "fr-par"
}

variable "zone" {
  type    = string
  default = "fr-par-1"
}

variable "version_k8s" {
  description = "Version de Kubernetes"
  type        = string
  default     = "1.34"
}

variable "type_noeud" {
  # Les gabarits disponibles dépendent de la zone et évoluent : vérifiez la liste
  # avant la session avec « scw k8s node-type list » ou dans la console Scaleway.
  # Alternatives courantes si DEV1-L n'est plus proposé : PRO2-XXS, GP1-XS, PLAY2-MICRO.
  # ⚠️ Ces nœuds sont en x86_64 : voir ./setup/02b-images-multiarch.sh.
  description = "Gabarit des nœuds — il faut au moins 4 Go de RAM par nœud"
  type        = string
  default     = "DEV1-L"
}

variable "nombre_noeuds" {
  description = "2 minimum : les démonstrations de placement en ont besoin"
  type        = number
  default     = 2
}
