/*
  Module : storage/storageAccount.bicep
  Purpose: Deploy a StorageV2 account with hierarchical namespace (ADLS Gen2),
           SFTP enabled for external customer access via private endpoint,
           VNet service endpoint integration restricting public access,
           a blob container for Logic App log files,
           and a local SFTP user with SSH key authentication.

  Params : storageSubnetId  — from networking/vnet.bicep
           sshPublicKey     — SSH public key supplied by the external customer

  Outputs: storageAccountId, storageAccountName, blobEndpoint, blobContainerName
  Used by: networking/privateEndpoint.bicep  (storageAccountId)
           logicApp/logicApp.bicep           (blobEndpoint, blobContainerName)

  SFTP note
  ─────────
  Azure Blob Storage SFTP requires hierarchical namespace (isHnsEnabled: true).
  The SFTP service listens on port 22 of the blob service endpoint.
  Access is via: <storageAccountName>.blob.core.windows.net (port 22)
  SFTP username format: <storageAccountName>.<localUserName>

  Network access note
  ───────────────────
  Public access is denied by default. Only the storage service-endpoint subnet
  and trusted Azure services (Logic App, Azure Monitor) can reach the account.
  The private endpoint (deployed separately) provides the customer SFTP path.
*/

// ── Parameters ────────────────────────────────────────────────────────────────

@description('Workload name used in resource naming.')
param workload string = 'anomaly'

@description('Environment name.')
@allowed(['dev', 'prod'])
param env string

@description('Azure region. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Resource ID of the storage service-endpoint subnet — from networking/vnet.bicep.')
param storageSubnetId string

@description('Storage account SKU. Use Standard_LRS for dev and Standard_ZRS or Standard_GRS for prod.')
@allowed(['Standard_LRS', 'Standard_ZRS', 'Standard_GRS', 'Standard_RAGRS'])
param skuName string = 'Standard_LRS'

@description('SFTP local user name for the external customer (3–64 lowercase alphanumeric chars).')
@minLength(3)
@maxLength(64)
param sftpUserName string = 'sftpcustomer'

@description('SSH public key value provided by the external customer (OpenSSH format, e.g. ssh-rsa AAAA...).')
param sshPublicKey string

@description('Soft-delete retention period in days for blobs and containers (1–365).')
@minValue(1)
@maxValue(365)
param blobSoftDeleteDays int = 7

@description('Resource tags.')
param tags object = {}

// ── Variables ─────────────────────────────────────────────────────────────────

// Storage account name must be lowercase alphanumeric, max 24 chars — no hyphens allowed.
var storageAccountName = 'st${workload}${env}'

// Container name follows the project naming convention (hyphens are valid for containers).
var blobContainerName = 'logs-${workload}-${env}'

// ── Resources ─────────────────────────────────────────────────────────────────

// 1. Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: skuName
  }
  properties: {
    isHnsEnabled: true                    // Hierarchical namespace — required for SFTP
    isSftpEnabled: true                   // Enable SFTP (port 22) on blob endpoint
    isLocalUserEnabled: true              // Required to create SFTP local users
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false          // No anonymous public access to any container
    allowSharedKeyAccess: true            // Required for Logic App storage connection
    defaultToOAuthAuthentication: false
    accessTier: 'Hot'
    networkAcls: {
      defaultAction: 'Deny'              // Block all public traffic by default
      bypass: 'Logging, Metrics, AzureServices'  // Allow diagnostics + trusted Azure services
      virtualNetworkRules: [
        {
          id: storageSubnetId            // Allow access from the storage service-endpoint subnet
          action: 'Allow'
        }
      ]
      ipRules: []
    }
    encryption: {
      keySource: 'Microsoft.Storage'     // Microsoft-managed keys (default)
      services: {
        blob: { enabled: true, keyType: 'Account' }
        file: { enabled: true, keyType: 'Account' }
      }
    }
  }
}

// 2. Blob Service — enable soft delete to protect log files from accidental deletion
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: blobSoftDeleteDays
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: blobSoftDeleteDays
    }
  }
}

// 3. Blob Container — target container for Logic App log files and SFTP uploads
resource blobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: blobContainerName
  properties: {
    publicAccess: 'None'                 // No public blob access on this container
  }
}

// 4. SFTP Local User — external customer uploads files via SFTP using SSH key auth
//    SFTP connection string: <storageAccountName>.blob.core.windows.net (port 22)
//    SFTP username:          <storageAccountName>.<sftpUserName>
//    Permissions on container: r=read, c=create, w=write, d=delete, l=list
resource sftpUser 'Microsoft.Storage/storageAccounts/localUsers@2023-01-01' = {
  parent: storageAccount
  name: sftpUserName
  properties: {
    permissionScopes: [
      {
        permissions: 'rcwdl'
        service: 'blob'
        resourceName: blobContainerName
      }
    ]
    homeDirectory: blobContainerName
    sshAuthorizedKeys: [
      {
        description: 'External customer SFTP key'
        key: sshPublicKey
      }
    ]
    hasSharedKey: false                  // Disable shared key auth for SFTP user
    hasSshPassword: false                // Disable password auth — SSH key only
  }
  dependsOn: [blobContainer]            // Container must exist before user is scoped to it
}

// ── Outputs ───────────────────────────────────────────────────────────────────

@description('Resource ID of the storage account — consumed by networking/privateEndpoint.bicep.')
output storageAccountId string = storageAccount.id

@description('Name of the storage account (stanomalydev / stanomalyprod).')
output storageAccountName string = storageAccount.name

@description('Primary blob service endpoint URL — consumed by logicApp/logicApp.bicep.')
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('Name of the blob container that holds Logic App log files and SFTP uploads.')
output blobContainerName string = blobContainer.name
