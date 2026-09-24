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
  # Vérifiez ce qui est proposé avant la session — Kapsule retire les versions
  # anciennes et n'accepte pas n'importe quel numéro :
  #   scw k8s version list
  #
  # ⚠️ La forme dépend de var.auto_maj :
  #   auto_maj = true  (défaut) → version MINEURE obligatoire, ex. « 1.34 »
  #   auto_maj = false          → version COMPLÈTE obligatoire, ex. « 1.34.3 »
  description = "Version de Kubernetes — mineure (1.34) si auto_maj, complète (1.34.3) sinon"
  type        = string
  default     = "1.34"
}

variable "auto_maj" {
  # Pour un cluster qui vit deux ou trois jours, l'auto-upgrade est le choix simple :
  # il évite d'aller relever le numéro de patch exact avant chaque session, et la
  # fenêtre de maintenance est placée hors des journées de formation.
  description = "Mise à niveau automatique des patches (impose une version mineure)"
  type        = bool
  default     = true
}

variable "fenetre_jour" {
  description = "Jour de la fenêtre de maintenance — monday…sunday, ou any"
  type        = string
  default     = "sunday"
}

variable "fenetre_heure" {
  description = "Heure UTC de début de la fenêtre de maintenance (0-23)"
  type        = number
  default     = 3
}

variable "registre" {
  description = "Nom du namespace Container Registry — unique pour tout Scaleway"
  type        = string
  default     = "ccs-shopix"
}

variable "type_noeud" {
  # Tarifs relevés sur scaleway.com en septembre 2026, hors stockage :
  #   DEV1-L       4 vCPU /  8 Go   0,04284 €/h   ~31 €/mois
  #   PLAY2-MICRO  4 vCPU /  8 Go   0,05508 €/h   ~40 €/mois
  #   PRO2-XXS     2 vCPU /  8 Go   0,05610 €/h   ~41 €/mois
  #   POP2-2C-8G   2 vCPU /  8 Go   0,07350 €/h   ~54 €/mois
  #   GP1-XS       4 vCPU / 16 Go   0,09282 €/h   ~68 €/mois
  # Un « node type » de pool Kapsule est un gabarit d'instance : il n'y a pas de
  # commande « scw k8s node-type list ». Pour vérifier ce qui est proposé :
  #   scw instance server-type list zone=fr-par-1
  # et si cette forme n'existe pas dans votre version de la CLI, la liste de référence
  # est l'écran de création de pool dans la console Kapsule. De toute façon,
  # « terraform apply » échoue en quelques secondes, avec un message explicite, si le
  # gabarit n'est pas disponible dans la zone : c'est un test suffisant.
  # 8 Go par nœud est le minimum utile ici : kube-prometheus-stack demande ~2 Go à lui
  # seul, plus Loki, plus ArgoCD, plus Shopix.
  # ⚠️ Ces nœuds sont en x86_64 : voir ./setup/02b-images-multiarch.sh.
  description = "Gabarit des nœuds — 8 Go de RAM par nœud pour la pile du J3"
  type        = string
  default     = "DEV1-L"
}

variable "nombre_noeuds" {
  description = "2 minimum : les démonstrations de placement en ont besoin"
  type        = number
  default     = 2
}
