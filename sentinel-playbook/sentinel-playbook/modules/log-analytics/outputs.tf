output "workspace_resource_id" {
  description = "Full ARM resource ID of the workspace (used for RBAC scoping and Sentinel onboarding)."
  value       = azurerm_log_analytics_workspace.this.id
}

output "workspace_customer_id" {
  description = "The workspace GUID (customer ID), used by some data-plane APIs."
  value       = azurerm_log_analytics_workspace.this.workspace_id
}

output "workspace_name" {
  value = azurerm_log_analytics_workspace.this.name
}
