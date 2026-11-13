variable "subscription_id" {
  description = "ID de la suscripción de Azure"
  type        = string
}

variable "location" {
  description = "Región (la escribe scripts/select-region.ps1 en region.auto.tfvars)"
  type        = string
}

variable "vm_size" {
  description = "Tamaño de VM (lo escribe el script)"
  type        = string
}

variable "prefix" {
  description = "Prefijo para nombrar recursos"
  type        = string
  default     = "labping"
}

variable "address_space" {
  type    = list(string)
  default = ["10.10.0.0/16"]
}

variable "subnet_prefixes" {
  type    = list(string)
  default = ["10.10.1.0/24"]
}

variable "admin_username" {
  type    = string
  default = "azureuser"
}

variable "vm_names" {
  type    = list(string)
  default = ["vm1", "vm2"]
}

variable "tags" {
  type = map(string)
  default = {
    proyecto = "terraform-azure-ping"
    entorno  = "lab"
  }
}