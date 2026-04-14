# IaCPOC — Azure Bicep Infrastructure as Code

## Overview

This project deploys a fully integrated Azure solution using Bicep IaC.
All resources are deployed manually through the **VSCode Azure extension** — no scripts required.

### What This Deploys

| Component | Azure Resource | Purpose |
|---|---|---|
| Log Analytics Workspace | `law-anomaly-{env}` | Receives custom log tables from the Logic App |
| Virtual Network | `vnet-anomaly-{env}` | Isolates resources; hosts service-endpoint and PE subnets |
| Storage Account (ADLS Gen2) | `stanomalydev` / `stanomalyprod` | Stores log files; SFTP-enabled for external customer |
| Private Endpoint | `pe-anomaly-{env}` | Provides private, secure SFTP access into the storage account |
| Logic App (Consumption) | `la-anomaly-{env}` | Reads blobs daily and sends content to Log Analytics |

### Architecture

```
External Customer
      │
      │ SFTP (port 22, SSH key auth)
      ▼
┌─────────────────────────────────────────────────────────┐
│  Private Endpoint  (pe-anomaly-{env})                   │
│  DNS Zone: privatelink.blob.core.windows.net            │
└───────────────────────┬─────────────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────────────┐
│  Storage Account  (stanomalydev / stanomalyprod)        │
│  ├── SFTP enabled  (isHnsEnabled + isSftpEnabled)       │
│  ├── Blob container: logs-anomaly-{env}                 │
│  ├── VNet service endpoint → snet-anomaly-storage-{env} │
│  └── Network ACL: default deny, bypass AzureServices   │
└───────────────────────┬─────────────────────────────────┘
                        │ reads blobs every 24h
┌───────────────────────▼─────────────────────────────────┐
│  Logic App  (la-anomaly-{env})                          │
│  ├── Trigger: Recurrence — daily at 00:00 UTC           │
│  ├── Action: List blobs in container                    │
│  ├── Action: For each blob → Get content                │
│  └── Action: Send to Log Analytics (AnomalyLogs_CL)    │
└───────────────────────┬─────────────────────────────────┘
                        │ writes AnomalyLogs_CL table
┌───────────────────────▼─────────────────────────────────┐
│  Log Analytics Workspace  (law-anomaly-{env})           │
│  └── Custom table: AnomalyLogs_CL                       │
│      Fields: BlobName_s, RawContent_s, IngestionTime_t  │
└─────────────────────────────────────────────────────────┘

Virtual Network (vnet-anomaly-{env})  10.0.0.0/16
  ├── snet-anomaly-storage-{env}      10.0.1.0/24  (service endpoint)
  └── snet-anomaly-pe-{env}           10.0.2.0/24  (private endpoint)
```

---

## Prerequisites

| Requirement | Details |
|---|---|
| Azure subscription | `anomalySub` — Contributor access required |
| Resource group | `rg-anomaly-dev` and/or `rg-anomaly-prod` — must exist before deployment |
| VSCode | With **Bicep** extension and **Azure Resources** extension installed |
| Customer SSH key | OpenSSH public key from the external SFTP customer |

### Create the Resource Group (one-time)

In Azure portal or Azure CLI:
```bash
az group create --name rg-anomaly-dev  --location westeurope
az group create --name rg-anomaly-prod --location westeurope
```

---

## Folder Structure

```
IaCPOC/
├── main.bicep                              ← Deploy this file from VSCode
├── bicepconfig.json                        ← Linting rules (project-wide)
│
├── modules/
│   ├── monitoring/
│   │   └── logAnalyticsWorkspace.bicep     ← Step 1: Log Analytics Workspace
│   ├── networking/
│   │   ├── vnet.bicep                      ← Step 2a: VNet + subnets
│   │   └── privateEndpoint.bicep           ← Step 2b: Private Endpoint + DNS
│   ├── storage/
│   │   └── storageAccount.bicep            ← Step 3: Storage, container, SFTP user
│   └── logicApp/
│       └── logicApp.bicep                  ← Step 4: Logic App workflow + connections
│
├── parameters/
│   ├── dev.bicepparam                      ← Dev environment values
│   └── prod.bicepparam                     ← Prod environment values
│
└── docs/
    ├── project-structure.md                ← Folder layout rationale
    ├── file-creation-order.md              ← Module dependency order
    ├── dependencies.md                     ← Dependency diagram (Mermaid)
    └── naming-convention.md                ← Locked naming rules
```

---

## Naming Convention

**Pattern:** `{resource-type}-{workload}-{environment}` — kebab-case, no region segment.

| Resource | Dev | Prod |
|---|---|---|
| Resource Group | `rg-anomaly-dev` | `rg-anomaly-prod` |
| Virtual Network | `vnet-anomaly-dev` | `vnet-anomaly-prod` |
| Subnet (storage) | `snet-anomaly-storage-dev` | `snet-anomaly-storage-prod` |
| Subnet (PE) | `snet-anomaly-pe-dev` | `snet-anomaly-pe-prod` |
| Private Endpoint | `pe-anomaly-dev` | `pe-anomaly-prod` |
| **Storage Account** | `stanomalydev` | `stanomalyprod` |
| Blob Container | `logs-anomaly-dev` | `logs-anomaly-prod` |
| Logic App | `la-anomaly-dev` | `la-anomaly-prod` |
| Log Analytics Workspace | `law-anomaly-dev` | `law-anomaly-prod` |

> **Storage account exception:** Azure prohibits hyphens in storage account names.
> Pattern used: `st` + workload + environment (no separators).

---

## How to Deploy

### Step 1 — Update the SSH public key

Open the appropriate parameter file and replace the placeholder:

```
parameters/dev.bicepparam   → param sshPublicKey = 'ssh-rsa AAAA...'
parameters/prod.bicepparam  → param sshPublicKey = 'ssh-rsa AAAA...'
```

### Step 2 — Deploy from VSCode

1. Open `main.bicep` in VSCode
2. Right-click anywhere in the file
3. Select **"Deploy Bicep File..."**
4. Choose your **Azure subscription** (`anomalySub`)
5. Choose the **resource group** (`rg-anomaly-dev` or `rg-anomaly-prod`)
6. When prompted for a parameter file, select `parameters/dev.bicepparam` or `parameters/prod.bicepparam`
7. Confirm — Azure deploys all resources in dependency order

### Deployment Order (enforced automatically by Bicep)

```
main.bicep orchestrates:

  [parallel]  monitoring  ──┐
  [parallel]  vnet        ──┤
                            ↓
                        storage  ──────────────────────────────┐
                            ↓                                  │
                      privateEndpoint ← (needs storage + vnet) │
                            ↓                                  │
                        logicApp ← (needs storage + monitoring)┘
```

---

## Module Reference

### `modules/monitoring/logAnalyticsWorkspace.bicep`

Creates a Log Analytics Workspace. Deployed first — no dependencies.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `workload` | string | `'anomaly'` | Workload name (part of resource name) |
| `env` | string | — | `dev` or `prod` |
| `location` | string | RG location | Azure region |
| `retentionInDays` | int | `30` | Log retention (30–730 days) |
| `dailyQuotaGb` | int | `-1` | Daily cap in GB (-1 = unlimited) |
| `tags` | object | `{}` | Resource tags |

| Output | Type | Description |
|---|---|---|
| `workspaceId` | string | Full resource ID — passed to logicApp module |
| `workspaceName` | string | Workspace name |
| `customerId` | string | Workspace GUID — used by HTTP Data Collector API |

---

### `modules/networking/vnet.bicep`

Creates the VNet with two subnets. Deployed in parallel with monitoring.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `workload` | string | `'anomaly'` | Workload name |
| `env` | string | — | `dev` or `prod` |
| `location` | string | RG location | Azure region |
| `vnetAddressPrefix` | string | `'10.0.0.0/16'` | VNet CIDR |
| `storageSubnetPrefix` | string | `'10.0.1.0/24'` | Storage subnet CIDR |
| `peSubnetPrefix` | string | `'10.0.2.0/24'` | Private endpoint subnet CIDR |
| `tags` | object | `{}` | Resource tags |

| Output | Type | Description |
|---|---|---|
| `vnetId` | string | VNet resource ID — passed to privateEndpoint |
| `vnetName` | string | VNet name |
| `storageSubnetId` | string | Storage subnet resource ID — passed to storage |
| `privateEndpointSubnetId` | string | PE subnet resource ID — passed to privateEndpoint |

---

### `modules/storage/storageAccount.bicep`

Creates the storage account (ADLS Gen2 + SFTP), blob container, and SFTP local user.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `workload` | string | `'anomaly'` | Workload name |
| `env` | string | — | `dev` or `prod` |
| `location` | string | RG location | Azure region |
| `storageSubnetId` | string | — | **From vnet.outputs.storageSubnetId** |
| `skuName` | string | `'Standard_LRS'` | Storage SKU |
| `sftpUserName` | string | `'sftpcustomer'` | SFTP local user name |
| `sshPublicKey` | string | — | Customer SSH public key |
| `blobSoftDeleteDays` | int | `7` | Soft-delete retention (1–365 days) |
| `tags` | object | `{}` | Resource tags |

| Output | Type | Description |
|---|---|---|
| `storageAccountId` | string | Resource ID — passed to privateEndpoint + logicApp |
| `storageAccountName` | string | Account name — passed to logicApp |
| `blobEndpoint` | string | Blob service URL |
| `blobContainerName` | string | Container name — passed to logicApp |

**SFTP connection details** (post-deployment):
- Host: `<storageAccountName>.blob.core.windows.net` port `22`
- Username: `<storageAccountName>.<sftpUserName>`
- Authentication: SSH public key

---

### `modules/networking/privateEndpoint.bicep`

Creates the private endpoint, private DNS zone, VNet link, and DNS zone group.
Deployed after storage — requires `storageAccountId`.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `workload` | string | `'anomaly'` | Workload name |
| `env` | string | — | `dev` or `prod` |
| `location` | string | RG location | Azure region |
| `privateEndpointSubnetId` | string | — | **From vnet.outputs.privateEndpointSubnetId** |
| `storageAccountId` | string | — | **From storage.outputs.storageAccountId** |
| `vnetId` | string | — | **From vnet.outputs.vnetId** |
| `tags` | object | `{}` | Resource tags |

| Output | Type | Description |
|---|---|---|
| `privateEndpointId` | string | PE resource ID |

**DNS resolution:** The private DNS zone `privatelink.blob.core.windows.net` is linked to the VNet.
Any client inside the VNet resolves `stanomalydev.blob.core.windows.net` to the PE's private IP.

---

### `modules/logicApp/logicApp.bicep`

Creates the Logic App Consumption workflow and both API connections.
Deployed last — depends on storage and monitoring.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `workload` | string | `'anomaly'` | Workload name |
| `env` | string | — | `dev` or `prod` |
| `location` | string | RG location | Azure region |
| `storageAccountId` | string | — | **From storage.outputs.storageAccountId** |
| `storageAccountName` | string | — | **From storage.outputs.storageAccountName** |
| `blobContainerName` | string | — | **From storage.outputs.blobContainerName** |
| `workspaceResourceId` | string | — | **From monitoring.outputs.workspaceId** |
| `workspaceCustomerId` | string | — | **From monitoring.outputs.customerId** |
| `tags` | object | `{}` | Resource tags |

| Output | Type | Description |
|---|---|---|
| `logicAppId` | string | Logic App resource ID |
| `logicAppName` | string | Logic App name |
| `logicAppPrincipalId` | string | Managed identity principal ID (for RBAC) |

**Workflow logic:**
1. **Trigger** — Recurrence every 24 hours at midnight UTC
2. **List blobs** — Lists all blobs in `logs-anomaly-{env}` container
3. **For each blob** — Reads content sequentially (concurrency = 1)
4. **Send to Log Analytics** — POSTs to the HTTP Data Collector API
   - Table created: `AnomalyLogs_CL`
   - Fields: `BlobName_s`, `RawContent_s`, `IngestionTime_t`

---

## Parameters Reference

### `parameters/dev.bicepparam`

| Parameter | Value | Notes |
|---|---|---|
| `env` | `'dev'` | |
| `sshPublicKey` | *(replace)* | Customer's SSH public key |
| `skuName` | `'Standard_LRS'` | Locally redundant |
| `retentionInDays` | `30` | Minimum — cost-efficient |
| `dailyQuotaGb` | `1` | 1 GB/day cap for dev |
| `blobSoftDeleteDays` | `7` | |
| VNet CIDRs | `10.0.x.x/24` | |

### `parameters/prod.bicepparam`

| Parameter | Value | Notes |
|---|---|---|
| `env` | `'prod'` | |
| `sshPublicKey` | *(replace)* | Customer's SSH public key |
| `skuName` | `'Standard_ZRS'` | Zone-redundant |
| `retentionInDays` | `90` | 90 days for compliance |
| `dailyQuotaGb` | `-1` | No cap |
| `blobSoftDeleteDays` | `30` | Extended for production data protection |
| VNet CIDRs | `10.1.x.x/24` | Separate range from dev |

---

## Post-Deployment Steps

### 1 — Verify SFTP connectivity

Test the SFTP connection from the customer's environment:
```bash
sftp -P 22 stanomalydev.sftpcustomer@stanomalydev.blob.core.windows.net
```
The customer must use their SSH private key (matching the public key deployed).

### 2 — Verify Logic App runs

- Navigate to `la-anomaly-{env}` in Azure portal
- Click **Run Trigger** → **Recurrence_Every_24_Hours** to trigger a manual run
- Check **Run History** for success or failure details

### 3 — Query Log Analytics

After the first successful Logic App run, query the custom table in Log Analytics:
```kql
AnomalyLogs_CL
| order by TimeGenerated desc
| take 100
```

### 4 — Authorize Logic App API Connections

After deployment, the API connections may need explicit authorization in the Azure portal:
1. Navigate to `conn-anomaly-blob-{env}` → **Edit API connection** → **Authorize**
2. Navigate to `conn-anomaly-law-{env}` → **Edit API connection** → **Authorize**

---

## Security Considerations

| Area | Current (POC) | Recommended (Production) |
|---|---|---|
| Storage auth (Logic App) | Shared account key via API connection | Managed identity + `Storage Blob Data Reader` role |
| Log Analytics auth | Workspace primary key via API connection | Managed identity + `Log Analytics Contributor` role |
| SFTP auth | SSH public key only (no password) | ✅ Already using best practice |
| Network | Service endpoint + private endpoint | ✅ Already implemented |
| TLS | TLS 1.2 minimum | ✅ Already enforced |
| Public blob access | Disabled | ✅ Already disabled |
| Soft delete | Enabled (7d dev / 30d prod) | ✅ Already enabled |

---

## Linting

The `bicepconfig.json` at the project root enforces these rules across all `.bicep` files:

| Rule | Level |
|---|---|
| `no-unused-params` | warning |
| `no-unused-vars` | warning |
| `prefer-interpolation` | warning |
| `secure-secrets-in-params` | **error** |

The Bicep VSCode extension reports violations inline as you type.
