output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "log_analytics_workspace_resource_id" {
  value = module.log_analytics.workspace_resource_id
}

output "log_analytics_workspace_customer_id" {
  value = module.log_analytics.workspace_customer_id
}

output "logic_app_name" {
  value = module.playbook.logic_app_name
}

output "logic_app_default_hostname" {
  value = module.playbook.default_hostname
}

output "logic_app_managed_identity_principal_id" {
  value = module.playbook.principal_id
}

output "next_step_get_webhook_url" {
  value       = "Terraform cannot output the trigger callback URL because Standard Logic App workflow triggers are not ARM resources. After 'terraform apply', run the az cli command in README.md (section 'Retrieve the webhook URL') to fetch it."
  description = "Manual follow-up step"
}
