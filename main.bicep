/*
  File    : main.bicep
  Purpose : Orchestration entry point for the IaCPOC solution.
            Deploys all modules in dependency order and wires their
            outputs to the inputs of downstream modules.
            This is the ONLY file deployed directly from VSCode.

  Deploy  : Right-click this file in VSCode → "Deploy Bicep File..."
            Select subscription → resource group → parameter file.

  Module deploy order (enforced by output→input dependencies):
    1. monitoring   — Log Analytics Workspace (no dependencies)
    2. vnet         — Virtual Network + subnets (no dependencies)
    3. storage      — Storage Account + container + SFTP user (needs vnet)
    4. privateEndpoint — PE + DNS zone (needs vnet + storage)
    5. logicApp     — Workflow + connections (needs storage + monitoring)
*/

targetScope = 'resourceGroup'

// ── Parameters ────────────────────────────────────────────────────────────────

@description('Workload identifier — used in every resource name. Default: anomaly.')
param workload string = 'anomaly'

@description('Deployment environment. Controls resource name suffixes and environment-specific defaults.')
@allowed(['dev', 'prod'])
param env string

@description('Azure region for all resources. Defaults to the resource group location.')
param location string = resourceGroup().location

// ── Storage / SFTP ────────────────────────────────────────────────────────────

@description('SSH public key provided by the external SFTP customer (OpenSSH format: ssh-rsa AAAA...).')
param sshPublicKey string

@description('SFTP local user name for the external customer.')
@minLength(3)
@maxLength(64)
param sftpUserName string = 'sftpcustomer'

@description('Storage account SKU. Standard_LRS for dev; Standard_ZRS or Standard_GRS for prod.')
@allowed(['Standard_LRS', 'Standard_ZRS', 'Standard_GRS', 'Standard_RAGRS'])
param skuName string = 'Standard_LRS'

@description('Blob/container soft-delete retention in days (1–365).')
@minValue(1)
@maxValue(365)
param blobSoftDeleteDays int = 7

// ── Networking ────────────────────────────────────────────────────────────────

@description('VNet address space (CIDR). Must not overlap with other VNets.')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Storage service-endpoint subnet CIDR. Must be within vnetAddressPrefix.')
param storageSubnetPrefix string = '10.0.1.0/24'

@description('Private endpoint subnet CIDR. Must be within vnetAddressPrefix.')
param peSubnetPrefix string = '10.0.2.0/24'

// ── Monitoring ────────────────────────────────────────────────────────────────

@description('Log Analytics log retention in days (30–730).')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

@description('Log Analytics daily ingestion cap in GB. -1 = no cap.')
param dailyQuotaGb int = -1

// ── Tags ──────────────────────────────────────────────────────────────────────

@description('Resource tags applied to every resource in the solution.')
param tags object = {}

// ── Module: Monitoring (Step 1) ───────────────────────────────────────────────
// No dependencies — deployed first.

module monitoring 'modules/monitoring/logAnalyticsWorkspace.bicep' = {
  name: 'deploy-monitoring'
  params: {
    workload: workload
    env: env
    location: location
    retentionInDays: retentionInDays
    dailyQuotaGb: dailyQuotaGb
    tags: tags
  }
}

// ── Module: VNet (Step 2) ─────────────────────────────────────────────────────
// No dependencies — deployed in parallel with monitoring.

module vnet 'modules/networking/vnet.bicep' = {
  name: 'deploy-vnet'
  params: {
    workload: workload
    env: env
    location: location
    vnetAddressPrefix: vnetAddressPrefix
    storageSubnetPrefix: storageSubnetPrefix
    peSubnetPrefix: peSubnetPrefix
    tags: tags
  }
}

// ── Module: Storage (Step 3) ──────────────────────────────────────────────────
// Depends on: vnet (storageSubnetId)

module storage 'modules/storage/storageAccount.bicep' = {
  name: 'deploy-storage'
  params: {
    workload: workload
    env: env
    location: location
    storageSubnetId: vnet.outputs.storageSubnetId
    skuName: skuName
    sftpUserName: sftpUserName
    sshPublicKey: sshPublicKey
    blobSoftDeleteDays: blobSoftDeleteDays
    tags: tags
  }
}

// ── Module: Private Endpoint (Step 4) ────────────────────────────────────────
// Depends on: vnet (vnetId, privateEndpointSubnetId) + storage (storageAccountId)
// Deployed AFTER storage so that storageAccountId is available.

module privateEndpoint 'modules/networking/privateEndpoint.bicep' = {
  name: 'deploy-private-endpoint'
  params: {
    workload: workload
    env: env
    location: location
    privateEndpointSubnetId: vnet.outputs.privateEndpointSubnetId
    storageAccountId: storage.outputs.storageAccountId
    vnetId: vnet.outputs.vnetId
    tags: tags
  }
}

// ── Module: Logic App (Step 5) ────────────────────────────────────────────────
// Depends on: storage (storageAccountId, storageAccountName, blobContainerName)
//             monitoring (workspaceId → workspaceResourceId, customerId)
// Deployed LAST — top of the dependency tree.

module logicApp 'modules/logicApp/logicApp.bicep' = {
  name: 'deploy-logicapp'
  params: {
    workload: workload
    env: env
    location: location
    storageAccountId: storage.outputs.storageAccountId
    storageAccountName: storage.outputs.storageAccountName
    blobContainerName: storage.outputs.blobContainerName
    workspaceResourceId: monitoring.outputs.workspaceId
    workspaceCustomerId: monitoring.outputs.customerId
    tags: tags
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

@description('Resource ID of the Log Analytics Workspace.')
output logAnalyticsWorkspaceId string = monitoring.outputs.workspaceId

@description('Name of the Log Analytics Workspace.')
output logAnalyticsWorkspaceName string = monitoring.outputs.workspaceName

@description('Name of the storage account.')
output storageAccountName string = storage.outputs.storageAccountName

@description('Primary blob service endpoint URL.')
output blobEndpoint string = storage.outputs.blobEndpoint

@description('Name of the blob container used by the Logic App.')
output blobContainerName string = storage.outputs.blobContainerName

@description('SFTP hostname — connect via sftp on port 22.')
output sftpHostname string = '${storage.outputs.storageAccountName}.blob.core.windows.net'

@description('SFTP username for the external customer (<storageAccountName>.<sftpUserName>).')
output sftpUsername string = '${storage.outputs.storageAccountName}.${sftpUserName}'

@description('Resource ID of the storage account private endpoint.')
output privateEndpointId string = privateEndpoint.outputs.privateEndpointId

@description('Name of the Logic App workflow.')
output logicAppName string = logicApp.outputs.logicAppName

@description('Principal ID of the Logic App managed identity — use for RBAC role assignments.')
output logicAppPrincipalId string = logicApp.outputs.logicAppPrincipalId
