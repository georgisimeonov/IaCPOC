resource "azurerm_sentinel_log_analytics_workspace_onboarding" "this" {
  workspace_id                 = var.workspace_resource_id
  customer_managed_key_enabled = false
}
