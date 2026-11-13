resource "azurerm_resource_group" "this" {
  name     = "rg-${var.prefix}"
  location = var.location
  tags     = var.tags
}

module "network" {
  source              = "./modules/network"
  prefix              = var.prefix
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = var.address_space
  subnet_prefixes     = var.subnet_prefixes
  tags                = var.tags
}

module "compute" {
  source              = "./modules/compute"
  prefix              = var.prefix
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = module.network.subnet_id
  vm_names            = var.vm_names
  vm_size             = var.vm_size
  admin_username      = var.admin_username
  tags                = var.tags
}