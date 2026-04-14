// ── dev.bicepparam ────────────────────────────────────────────────────────────
// Parameter file for the DEVELOPMENT environment.
// Deploy via VSCode: right-click main.bicep → Deploy Bicep File → select this file.
//
// Required before deploying:
//   1. Create resource group:  rg-anomaly-dev  (in Azure portal or az CLI)
//   2. Replace sshPublicKey with the actual public key from the external customer.
// ─────────────────────────────────────────────────────────────────────────────

using '../main.bicep'

// ── Required ──────────────────────────────────────────────────────────────────

param env = 'dev'

// Replace with the actual SSH public key provided by the external SFTP customer.
// Format: 'ssh-rsa AAAA...  user@host'
param sshPublicKey = 'ssh-rsa AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA customer@example.com'

// ── Networking ────────────────────────────────────────────────────────────────

param vnetAddressPrefix   = '10.0.0.0/16'
param storageSubnetPrefix = '10.0.1.0/24'
param peSubnetPrefix      = '10.0.2.0/24'

// ── Storage ───────────────────────────────────────────────────────────────────

param skuName          = 'Standard_LRS'   // Locally redundant — sufficient for dev
param sftpUserName     = 'sftpcustomer'
param blobSoftDeleteDays = 7

// ── Monitoring ────────────────────────────────────────────────────────────────

param retentionInDays = 30                // Minimum retention — cost-efficient for dev
param dailyQuotaGb    = 1                 // 1 GB/day cap to limit dev costs

// ── Tags ──────────────────────────────────────────────────────────────────────

param tags = {
  environment: 'dev'
  workload:    'anomaly'
  managedBy:   'bicep'
  costCenter:  'engineering'
}
