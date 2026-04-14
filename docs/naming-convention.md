# IaCPOC — Naming Convention (Locked)

## Pattern

```
{resource-type}-{workload}-{environment}
```

| Segment          | Value          | Notes                              |
|------------------|----------------|------------------------------------|
| `resource-type`  | CAF prefix     | See table below                    |
| `workload`       | `anomaly`      | Fixed for this project             |
| `environment`    | `dev` / `prod` | Appended to every resource name    |

Style: **kebab-case**, all lowercase. No region segment.

---

## Resource Name Reference

| Resource                   | Type prefix | Dev name                    | Prod name                    |
|----------------------------|-------------|---------------------------  |------------------------------|
| Subscription               | —           | `anomalySub`                | `anomalySub`                 |
| Resource Group             | `rg`        | `rg-anomaly-dev`            | `rg-anomaly-prod`            |
| Virtual Network            | `vnet`      | `vnet-anomaly-dev`          | `vnet-anomaly-prod`          |
| Subnet (storage)           | `snet`      | `snet-anomaly-storage-dev`  | `snet-anomaly-storage-prod`  |
| Subnet (private endpoint)  | `snet`      | `snet-anomaly-pe-dev`       | `snet-anomaly-pe-prod`       |
| Private Endpoint           | `pe`        | `pe-anomaly-dev`            | `pe-anomaly-prod`            |
| Storage Account            | `st`        | `stanomalydev`              | `stanomalyprod`              |
| Blob Container             | —           | `logs-anomaly-dev`          | `logs-anomaly-prod`          |
| Logic App                  | `la`        | `la-anomaly-dev`            | `la-anomaly-prod`            |
| Log Analytics Workspace    | `law`       | `law-anomaly-dev`           | `law-anomaly-prod`           |

---

## Important Exception — Storage Account

Azure storage account names **cannot contain hyphens**. They must be:
- 3–24 characters
- Lowercase alphanumeric only

Convention for storage accounts: `st` + workload + environment, no separators.

```
✅ stanomalydev
❌ st-anomaly-dev   ← invalid in Azure
```

---

## Bicep Variables (to be used in main.bicep)

```bicep
var workload = 'anomaly'
var env      = 'dev'         // passed in as param

var names = {
  resourceGroup:      'rg-${workload}-${env}'
  vnet:               'vnet-${workload}-${env}'
  subnetStorage:      'snet-${workload}-storage-${env}'
  subnetPe:           'snet-${workload}-pe-${env}'
  privateEndpoint:    'pe-${workload}-${env}'
  storageAccount:     'st${workload}${env}'
  blobContainer:      'logs-${workload}-${env}'
  logicApp:           'la-${workload}-${env}'
  logAnalytics:       'law-${workload}-${env}'
}
```
