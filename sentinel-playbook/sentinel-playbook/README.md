# Sentinel + Standard Logic App Playbook

Terraform that provisions:

- **Log Analytics workspace** (`modules/log-analytics`)
- **Microsoft Sentinel**, onboarded to that workspace (`modules/sentinel`)
- **Standard Logic App** acting as a Sentinel playbook (`modules/logic-app-standard`), with:
  - A system-assigned managed identity granted the **Microsoft Sentinel Responder** role, scoped to the workspace — enough to read and change incident status/classification, nothing broader.
  - A workflow (`update-incident-status`) exposed as an HTTP webhook. It takes an incident ARM ID + desired status, fetches the incident's current `etag`, and PATCHes the status via the Sentinel/ARM REST API using the managed identity — no API keys, no Sentinel connector, no stored credentials.

## Why Standard Logic App workflows are handled differently

Consumption Logic Apps have first-class Terraform resources for triggers and actions (`azurerm_logic_app_trigger_http_request`, etc.). **Standard** Logic Apps don't — a workflow is a `workflow.json` file living in the app's file system, not an ARM sub-resource. So this project:

1. Provisions the Standard Logic App *shell* (storage account, WS1 service plan, the app itself, RBAC) with normal `azurerm_*` resources.
2. Zips `workflow_app/` (which contains `host.json`, `connections.json`, and `update-incident-status/workflow.json`) and deploys it with `az logicapp deployment source config-zip` via a `null_resource` local-exec, re-triggered whenever the zip hash changes.

This means the Azure CLI must be installed and already authenticated (`az login`) wherever you run `terraform apply` — the provisioner shells out to it.

## Structure

```
sentinel-playbook/
├── main.tf / variables.tf / outputs.tf / providers.tf
├── terraform.tfvars.example
└── modules/
    ├── log-analytics/
    ├── sentinel/
    └── logic-app-standard/
        └── workflow_app/
            ├── host.json
            ├── connections.json
            └── update-incident-status/
                └── workflow.json
```

## Deploy

```bash
az login
az account set --subscription "<subscription-id>"

cp terraform.tfvars.example terraform.tfvars   # adjust names/region as needed

terraform init
terraform plan
terraform apply
```

## Retrieve the webhook URL

Because the trigger isn't an ARM resource, Terraform can't output its callback URL directly. After `apply` succeeds, fetch it with:

```bash
RG=$(terraform output -raw resource_group_name)
APP=$(terraform output -raw logic_app_name)

az rest --method post \
  --uri "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RG}/providers/Microsoft.Web/sites/${APP}/hostruntime/runtime/webhooks/workflow/api/management/workflows/update-incident-status/triggers/manual/listCallbackUrl?api-version=2018-11-01"
```

The response body's `value` field is the callback URL to POST to.

## Test it

```bash
curl -X POST "<callback-url-from-above>" \
  -H "Content-Type: application/json" \
  -d '{
        "incidentArmId": "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<law>/providers/Microsoft.SecurityInsights/incidents/<incident-guid>",
        "status": "Closed",
        "classification": "TruePositive",
        "classificationComment": "Confirmed via automated playbook"
      }'
```

## Extending

- **Trigger from Sentinel automation rules**: create an `azurerm_sentinel_automation_rule` that calls this Logic App via its Azure Resource Manager connector action, or POST to the webhook from an analytics-rule-driven automation elsewhere.
- **More actions**: add sibling folders under `workflow_app/` (e.g. `enrich-incident/`, `notify-teams/`) each with their own `workflow.json` — they all deploy in the same zip.
- **Tighter RBAC**: `Microsoft Sentinel Responder` allows status/classification/assignment changes but not deleting incidents or editing analytics rules. Swap in a custom role definition if you need something narrower.
