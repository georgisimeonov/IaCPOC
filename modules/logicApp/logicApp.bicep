/*
  Module : logicApp/logicApp.bicep
  Purpose: Deploy a Logic App Consumption workflow that:
             - triggers daily at midnight UTC (Recurrence, every 24 hours)
             - lists all blob files in the log container
             - reads each blob and sends its content to a Log Analytics custom table
  Params : storageAccountId, storageAccountName, blobContainerName
             — from storage/storageAccount.bicep
           workspaceResourceId, workspaceCustomerId
             — from monitoring/logAnalyticsWorkspace.bicep
  Outputs: logicAppId, logicAppName

  API connections
  ───────────────
  Two managed API connections are deployed alongside the workflow:
    conn-anomaly-blob-{env}  → Azure Blob Storage  (azureblob connector)
    conn-anomaly-law-{env}   → Log Analytics       (azureloganalyticsdatacollector connector)

  Authentication note
  ───────────────────
  Connections use shared keys (storage account key + workspace key) retrieved at
  deploy time via listKeys(). Keys are stored only in the connection resource —
  they are never written to any output or template parameter.
  For production, replace with managed identity authentication.

  Log Analytics table
  ───────────────────
  Data is written to the custom table: AnomalyLogs_CL
  (Azure automatically appends _CL to the Log-Type header value)
  Fields created: BlobName_s, RawContent_s, IngestionTime_t
*/

// ── Parameters ────────────────────────────────────────────────────────────────

@description('Workload name used in resource naming.')
param workload string = 'anomaly'

@description('Environment name.')
@allowed(['dev', 'prod'])
param env string

@description('Azure region. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Resource ID of the storage account — used by listKeys() to retrieve the access key.')
param storageAccountId string

@description('Name of the storage account — used to configure the blob API connection.')
param storageAccountName string

@description('Name of the blob container to read log files from — from storage/storageAccount.bicep.')
param blobContainerName string

@description('Full resource ID of the Log Analytics Workspace — used by listKeys() to retrieve the workspace key.')
param workspaceResourceId string

@description('Log Analytics Workspace customer ID (GUID, customerId) — used as the connection username.')
param workspaceCustomerId string

@description('Resource tags.')
param tags object = {}

// ── Variables ─────────────────────────────────────────────────────────────────

var workflowName  = 'la-${workload}-${env}'
var blobConnName  = 'conn-${workload}-blob-${env}'
var lawConnName   = 'conn-${workload}-law-${env}'
var logTypeName   = 'AnomalyLogs'   // Creates table AnomalyLogs_CL in Log Analytics

// Retrieve keys at deployment time — not exposed as outputs
var storageAccountKey = listKeys(storageAccountId, '2023-01-01').keys[0].value
var workspaceKey      = listKeys(workspaceResourceId, '2023-09-01').primarySharedKey

// Managed API resource IDs (subscription-scoped, per region)
var blobApiId = subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azureblob')
var lawApiId  = subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azureloganalyticsdatacollector')

// ── Resources ─────────────────────────────────────────────────────────────────

// 1. API Connection — Azure Blob Storage
//    accountName + accessKey are stored encrypted inside the connection resource.
resource blobConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: blobConnName
  location: location
  tags: tags
  properties: {
    displayName: blobConnName
    api: {
      id: blobApiId
    }
    parameterValues: {
      accountName: storageAccountName
      accessKey: storageAccountKey
    }
  }
}

// 2. API Connection — Azure Log Analytics Data Collector
//    username = workspace GUID (customerId), password = primary shared key
resource lawConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: lawConnName
  location: location
  tags: tags
  properties: {
    displayName: lawConnName
    api: {
      id: lawApiId
    }
    parameterValues: {
      username: workspaceCustomerId
      password: workspaceKey
    }
  }
}

// 3. Logic App Workflow
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: workflowName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'              // Managed identity — available for future RBAC upgrades
  }
  properties: {
    state: 'Enabled'
    // Wire the deployed connections into the workflow runtime
    parameters: {
      '$connections': {
        value: {
          azureblob: {
            id: blobApiId
            connectionId: blobConnection.id
            connectionName: blobConnection.name
          }
          azureloganalyticsdatacollector: {
            id: lawApiId
            connectionId: lawConnection.id
            connectionName: lawConnection.name
          }
        }
      }
    }
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        // ── Trigger: runs every 24 hours at midnight UTC ────────────────────
        Recurrence_Every_24_Hours: {
          type: 'Recurrence'
          recurrence: {
            frequency: 'Day'
            interval: 1
            startTime: '2024-01-01T00:00:00Z'   // Anchor at midnight UTC
            timeZone: 'UTC'
          }
        }
      }
      actions: {

        // ── Step 1: List all blobs in the target container ──────────────────
        // 'AccountNameFromSettings' is a connector keyword that maps to the
        // account name configured in the blob API connection.
        List_blobs_in_container: {
          type: 'ApiConnection'
          runAfter: {}
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azureblob\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/v3/datasets/@{encodeURIComponent(encodeURIComponent(\'AccountNameFromSettings\'))}/getfolderv4'
            queries: {
              folderId: '/${blobContainerName}'   // Bicep interpolation → /logs-anomaly-dev
              nextPageMarker: ''
              useFlatListing: true                // List all blobs recursively
            }
          }
        }

        // ── Step 2: Loop over each blob ─────────────────────────────────────
        For_each_blob: {
          type: 'Foreach'
          runAfter: {
            List_blobs_in_container: ['Succeeded']
          }
          foreach: '@body(\'List_blobs_in_container\')?[\'value\']'
          runtimeConfiguration: {
            concurrency: {
              repetitions: 1              // Process sequentially to avoid throttling
            }
          }
          actions: {

            // ── Step 2a: Read blob content ──────────────────────────────────
            Get_blob_content: {
              type: 'ApiConnection'
              runAfter: {}
              inputs: {
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'azureblob\'][\'connectionId\']'
                  }
                }
                method: 'get'
                path: '/v3/datasets/@{encodeURIComponent(encodeURIComponent(\'AccountNameFromSettings\'))}/GetFileContentV2'
                queries: {
                  identifier: '@items(\'For_each_blob\')?[\'Id\']'
                  inferContentType: true
                }
              }
            }

            // ── Step 2b: Send blob data to Log Analytics ────────────────────
            // Creates / updates table: AnomalyLogs_CL
            // Fields: BlobName_s, RawContent_s, IngestionTime_t
            Send_logs_to_Log_Analytics: {
              type: 'ApiConnection'
              runAfter: {
                Get_blob_content: ['Succeeded']
              }
              inputs: {
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
                  }
                }
                method: 'post'
                body: {
                  BlobName: '@{items(\'For_each_blob\')?[\'DisplayName\']}'
                  RawContent: '@{body(\'Get_blob_content\')}'
                  IngestionTime: '@{utcNow()}'
                }
                headers: {
                  'Log-Type': logTypeName         // Bicep var → 'AnomalyLogs' → table AnomalyLogs_CL
                }
                path: '/api/logs'
              }
            }

          }
        }

      }
      outputs: {}
    }
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

@description('Resource ID of the Logic App workflow.')
output logicAppId string = logicApp.id

@description('Name of the Logic App workflow (la-anomaly-dev / la-anomaly-prod).')
output logicAppName string = logicApp.name

@description('Principal ID of the system-assigned managed identity — use for future RBAC role assignments.')
output logicAppPrincipalId string = logicApp.identity.principalId
