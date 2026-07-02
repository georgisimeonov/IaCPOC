variable "resource_group_name" {
  description = "Name of the resource group that holds all Sentinel resources."
  type        = string
  default     = "rg-sentinel-prod"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "westeurope"
}

variable "workspace_name" {
  description = "Name of the Log Analytics workspace backing Sentinel."
  type        = string
  default     = "law-sentinel-prod"
}

variable "retention_in_days" {
  description = "Log Analytics data retention in days."
  type        = number
  default     = 90
}

variable "logic_app_name" {
  description = "Name of the Standard Logic App used as the Sentinel playbook."
  type        = string
  default     = "logic-sentinel-playbook"
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    environment = "prod"
    managed_by  = "terraform"
    workload    = "sentinel"
  }
}
