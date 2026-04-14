// ── prod.bicepparam ───────────────────────────────────────────────────────────
// Parameter file for the PRODUCTION environment.
// Deploy via VSCode: right-click main.bicep → Deploy Bicep File → select this file.
//
// Required before deploying:
//   1. Create resource group:  rg-anomaly-prod  (in Azure portal or az CLI)
//   2. Replace sshPublicKey with the actual public key from the external customer.
//   3. Review CIDR ranges — ensure they do not overlap with other prod VNets.
// ─────────────────────────────────────────────────────────────────────────────

using '../main.bicep'

// ── Required ──────────────────────────────────────────────────────────────────

param env = 'prod'

// Replace with the actual SSH public key provided by the external SFTP customer.
// Format: 'ssh-rsa AAAA...  user@host'
param sshPublicKey = 'ssh-rsa AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA customer@example.com'

// ── Networking ────────────────────────────────────────────────────────────────

param vnetAddressPrefix   = '10.1.0.0/16'  // Separate range from dev to allow future peering
param storageSubnetPrefix = '10.1.1.0/24'
param peSubnetPrefix      = '10.1.2.0/24'

// ── Storage ───────────────────────────────────────────────────────────────────

param skuName          = 'Standard_ZRS'   // Zone-redundant — recommended for production
param sftpUserName     = 'sftpcustomer'
param blobSoftDeleteDays = 30             // Longer retention for production data protection

// ── Monitoring ────────────────────────────────────────────────────────────────

param retentionInDays = 90               // 90 days retention for compliance
param dailyQuotaGb    = -1              // No cap in production — full ingestion allowed

// ── Tags ──────────────────────────────────────────────────────────────────────

param tags = {
  environment: 'prod'
  workload:    'anomaly'
  managedBy:   'bicep'
  costCenter:  'operations'
}
