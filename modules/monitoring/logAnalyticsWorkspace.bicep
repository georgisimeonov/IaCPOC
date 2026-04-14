/*
  Module : monitoring/logAnalyticsWorkspace.bicep
  Purpose: Deploy a Log Analytics Workspace.
  Outputs: workspaceId, workspaceName, customerId
  Used by: logicApp module (writes custom log table via HTTP Data Collector API)

  Note on workspace key
  ─────────────────────
  The Logic App module retrieves the primary shared key at deploy time using:
    listKeys(workspaceId, '2023-09-01').primarySharedKey
  The key is never stored as a plain-text output from this module.
*/

// ── Parameters ────────────────────────────────────────────────────────────────

@description('Workload name used in resource naming. Default: anomaly.')
param workload string = 'anomaly'

@description('Environment name — controls the resource name suffix.')
@allowed(['dev', 'prod'])
param env string

@description('Azure region. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Log retention period in days (30–730).')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

@description('Daily ingestion cap in GB. Use -1 for no cap.')
param dailyQuotaGb int = -1

@description('Resource tags applied to the workspace.')
param tags object = {}

// ── Variables ─────────────────────────────────────────────────────────────────

var workspaceName = 'law-${workload}-${env}'

// ── Resources ─────────────────────────────────────────────────────────────────

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: dailyQuotaGb
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

@description('Full resource ID of the Log Analytics Workspace.')
output workspaceId string = logAnalyticsWorkspace.id

@description('Name of the Log Analytics Workspace (law-anomaly-dev / law-anomaly-prod).')
output workspaceName string = logAnalyticsWorkspace.name

@description('Workspace GUID (customerId) — required by the HTTP Data Collector API.')
output customerId string = logAnalyticsWorkspace.properties.customerId
