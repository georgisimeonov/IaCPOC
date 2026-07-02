data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

module "log_analytics" {
  source = "./modules/log-analytics"

  name                = var.workspace_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  retention_in_days   = var.retention_in_days
  tags                = var.tags
}

module "sentinel" {
  source = "./modules/sentinel"

  workspace_resource_id = module.log_analytics.workspace_resource_id
}

# Standard Logic App acting as the Sentinel playbook, triggered via webhook,
# with a system-assigned identity granted rights to update incident status.
module "playbook" {
  source = "./modules/logic-app-standard"

  resource_group_name   = azurerm_resource_group.this.name
  location               = azurerm_resource_group.this.location
  logic_app_name          = var.logic_app_name
  workspace_resource_id   = module.log_analytics.workspace_resource_id
  subscription_id         = data.azurerm_client_config.current.subscription_id
  tags                    = var.tags

  depends_on = [module.sentinel]
}
