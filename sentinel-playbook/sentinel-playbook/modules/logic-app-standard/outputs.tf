output "logic_app_name" {
  value = azurerm_logic_app_standard.this.name
}

output "default_hostname" {
  value = azurerm_logic_app_standard.this.default_hostname
}

output "principal_id" {
  description = "Object ID of the Logic App's system-assigned managed identity."
  value       = azurerm_logic_app_standard.this.identity[0].principal_id
}
