/*
  Module : networking/privateEndpoint.bicep
  Purpose: Deploy a Private Endpoint for the storage account (blob sub-resource),
           a Private DNS Zone (privatelink.blob.core.windows.net),
           a VNet DNS link, and a DNS zone group for automatic A-record injection.
  Params : privateEndpointSubnetId  — from networking/vnet.bicep
           storageAccountId         — from storage/storageAccount.bicep
           vnetId                   — from networking/vnet.bicep
  Outputs: privateEndpointId
  NOTE   : main.bicep deploys this module AFTER both vnet and storageAccount modules,
           because storageAccountId is only available once storage is deployed.

  SFTP note
  ─────────
  SFTP on Azure Blob Storage runs on the blob service endpoint (port 22).
  The private endpoint groupId 'blob' covers both blob and SFTP traffic.
  No separate private endpoint is required for SFTP.
*/

// ── Parameters ────────────────────────────────────────────────────────────────

@description('Workload name used in resource naming.')
param workload string = 'anomaly'

@description('Environment name.')
@allowed(['dev', 'prod'])
param env string

@description('Azure region. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Resource ID of the subnet where the private endpoint will be placed.')
param privateEndpointSubnetId string

@description('Resource ID of the storage account to connect via private endpoint.')
param storageAccountId string

@description('Resource ID of the VNet — used to link the private DNS zone.')
param vnetId string

@description('Resource tags.')
param tags object = {}

// ── Variables ─────────────────────────────────────────────────────────────────

var privateEndpointName = 'pe-${workload}-${env}'
var privateDnsZoneName  = 'privatelink.blob.core.windows.net'
var vnetLinkName        = 'link-${workload}-${env}'

// ── Resources ─────────────────────────────────────────────────────────────────

// 1. Private Endpoint — connects to the storage account blob sub-resource
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: privateEndpointName
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: privateEndpointName
        properties: {
          privateLinkServiceId: storageAccountId
          groupIds: ['blob']           // 'blob' covers both blob access and SFTP (port 22)
        }
      }
    ]
  }
}

// 2. Private DNS Zone — resolves blob storage to the PE private IP inside the VNet
//    Location must be 'global' for all private DNS zone resources.
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneName
  location: 'global'
  tags: tags
}

// 3. VNet link — enables DNS resolution for the private zone within the VNet
resource vnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: vnetLinkName
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false    // auto-registration not needed for private endpoints
  }
}

// 4. DNS zone group — automatically creates an A-record in the DNS zone
//    when the private endpoint is provisioned, pointing to its NIC private IP.
resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config-blob'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
  dependsOn: [vnetLink]    // DNS zone must be linked to VNet before the group is created
}

// ── Outputs ───────────────────────────────────────────────────────────────────

@description('Resource ID of the Private Endpoint.')
output privateEndpointId string = privateEndpoint.id
