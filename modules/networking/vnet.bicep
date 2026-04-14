/*
  Module : networking/vnet.bicep
  Purpose: Deploy a Virtual Network with two subnets:
             - Storage subnet  : service endpoint to Microsoft.Storage
             - PE subnet       : hosts the storage account private endpoint
  Outputs: vnetId, vnetName, storageSubnetId, privateEndpointSubnetId
  Used by: storage module (storageSubnetId)
           privateEndpoint module (privateEndpointSubnetId, vnetId)
*/

// ── Parameters ────────────────────────────────────────────────────────────────

@description('Workload name used in resource naming.')
param workload string = 'anomaly'

@description('Environment name.')
@allowed(['dev', 'prod'])
param env string

@description('Azure region. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Address space for the Virtual Network (CIDR).')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Address prefix for the storage service-endpoint subnet (CIDR).')
param storageSubnetPrefix string = '10.0.1.0/24'

@description('Address prefix for the private endpoint subnet (CIDR).')
param peSubnetPrefix string = '10.0.2.0/24'

@description('Resource tags.')
param tags object = {}

// ── Variables ─────────────────────────────────────────────────────────────────

var vnetName          = 'vnet-${workload}-${env}'
var storageSubnetName = 'snet-${workload}-storage-${env}'
var peSubnetName      = 'snet-${workload}-pe-${env}'

// ── Resources ─────────────────────────────────────────────────────────────────

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
    subnets: [
      // Subnet 0 — storage service-endpoint subnet
      // Services in this subnet reach the storage account via Microsoft.Storage service endpoint.
      {
        name: storageSubnetName
        properties: {
          addressPrefix: storageSubnetPrefix
          serviceEndpoints: [
            { service: 'Microsoft.Storage' }
          ]
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      // Subnet 1 — private endpoint subnet
      // privateEndpointNetworkPolicies must be Disabled to allow PE creation.
      {
        name: peSubnetName
        properties: {
          addressPrefix: peSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

@description('Resource ID of the Virtual Network.')
output vnetId string = vnet.id

@description('Name of the Virtual Network.')
output vnetName string = vnet.name

@description('Resource ID of the storage service-endpoint subnet.')
output storageSubnetId string = '${vnet.id}/subnets/${storageSubnetName}'

@description('Resource ID of the private endpoint subnet.')
output privateEndpointSubnetId string = '${vnet.id}/subnets/${peSubnetName}'
