resource "random_string" "storage_suffix" {
  length  = 6
  special = false
  upper   = false
}

# Standard Logic Apps require their own storage account (workflow state, run history).
resource "azurerm_storage_account" "this" {
  name                     = "st${substr(replace(var.logic_app_name, "-", ""), 0, 12)}${random_string.storage_suffix.result}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version           = "TLS1_2"
  tags                     = var.tags
}

# WS1 = Workflow Standard tier, required for azurerm_logic_app_standard.
resource "azurerm_service_plan" "this" {
  name                = "asp-${var.logic_app_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Windows"
  sku_name            = "WS1"
  tags                = var.tags
}

resource "azurerm_logic_app_standard" "this" {
  name                       = var.logic_app_name
  resource_group_name       = var.resource_group_name
  location                   = var.location
  app_service_plan_id        = azurerm_service_plan.this.id
  storage_account_name       = azurerm_storage_account.this.name
  storage_account_access_key = azurerm_storage_account.this.primary_access_key
  version                    = "~4"

  site_config {
    ftps_state = "Disabled"
  }

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME     = "node"
    WEBSITE_NODE_DEFAULT_VERSION = "~18"
    AzureWebJobsStorage           = azurerm_storage_account.this.primary_connection_string
    WORKFLOWS_SUBSCRIPTION_ID     = var.subscription_id
    WORKFLOWS_RESOURCE_GROUP_NAME = var.resource_group_name
    WORKFLOWS_LOCATION_NAME       = var.location
  }

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# Grants the Logic App's managed identity permission to read and change
# Sentinel incident status/classification, scoped to this workspace only.
resource "azurerm_role_assignment" "sentinel_responder" {
  scope                = var.workspace_resource_id
  role_definition_name = "Microsoft Sentinel Responder"
  principal_id         = azurerm_logic_app_standard.this.identity[0].principal_id
}

# --- Workflow deployment -----------------------------------------------
# Standard Logic App workflows are files (workflow.json) inside the app's
# file system, not individual ARM resources like Consumption Logic Apps.
# Terraform has no native "trigger"/"action" resources for Standard apps,
# so the workflow bundle is zip-deployed via the Azure CLI.

data "archive_file" "workflow_zip" {
  type        = "zip"
  source_dir  = "${path.module}/workflow_app"
  output_path = "${path.module}/build/workflow.zip"
}

resource "null_resource" "deploy_workflow" {
  triggers = {
    zip_hash    = data.archive_file.workflow_zip.output_sha
    logic_app   = azurerm_logic_app_standard.this.name
  }

  provisioner "local-exec" {
    command = <<-EOT
      az logicapp deployment source config-zip \
        --resource-group ${var.resource_group_name} \
        --name ${azurerm_logic_app_standard.this.name} \
        --src ${data.archive_file.workflow_zip.output_path}
    EOT
  }

  depends_on = [
    azurerm_logic_app_standard.this,
    azurerm_role_assignment.sentinel_responder,
  ]
}
