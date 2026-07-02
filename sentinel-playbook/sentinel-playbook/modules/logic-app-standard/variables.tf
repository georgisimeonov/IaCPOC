variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "logic_app_name" {
  type = string
}

variable "workspace_resource_id" {
  description = "ARM resource ID of the Sentinel-onboarded Log Analytics workspace, used to scope the RBAC role assignment."
  type        = string
}

variable "subscription_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
