using '../main.bicep'

// ── Core ──────────────────────────────────────────────────────────────────

param location = 'norwayeast'
param environment = 'prod'
param workspaceName = 'law-monitoring-prod'
param appInsightsName = 'appi-monitoring-prod'
param retentionInDays = 90
param dailyQuotaGb = 10

// ── Action Group ──────────────────────────────────────────────────────────

param actionGroupShortName = 'mon-prod'

param emailReceivers = [
  {
    name: 'OpsTeam'
    emailAddress: 'YOUR-OPS-EMAIL@contoso.com'     // ← replace
  }
  {
    name: 'OnCall'
    emailAddress: 'YOUR-ONCALL-EMAIL@contoso.com'  // ← replace (must differ from OpsTeam)
  }
]

// Teams webhook: set up a Power Automate flow (see DEPLOY.md Step 7)
param webhookReceivers = [
  {
    name: 'TeamsOpsChannel'
    serviceUri: 'YOUR-POWER-AUTOMATE-URL'          // ← replace
  }
]

// ── Event Hub ─────────────────────────────────────────────────────────────
// Namespace names are globally unique in Azure.
// Use the first 8 characters of your subscription ID as a suffix.
// e.g. subscription xxxxxxxx-... → suffix is 'xxxxxxxx'

param eventHubNamespaceName = 'evhns-mon-prod-XXXXXXXX'  // ← replace suffix
param eventHubName = 'evh-monitoring-prod'
param eventHubSku = 'Standard'

// ── Diagnostics ───────────────────────────────────────────────────────────
// Leave a field empty ('') to skip that module.
// Fill in and redeploy once the resource exists in Azure.

// Front Door
param frontDoorProfileName = 'afd-monitoring-prod'
param frontDoorResourceGroupName = 'rg-monitoring-prod'

// Container Apps
param containerAppsEnvironmentName = 'cae-monitoring-prod'
param containerAppsResourceGroupName = 'rg-monitoring-prod'

// VNet Flow Logs
// Get VNet ID:           az network vnet show -g rg-network-prod -n vnet-monitoring-prod --query id -o tsv
// Get storage ID:        az storage account show -g rg-monitoring-prod -n stflowprodXXXXXXXX --query id -o tsv
param vnetName = 'vnet-monitoring-prod'
param vnetResourceId = '/subscriptions/YOUR-SUBSCRIPTION-ID/resourceGroups/rg-network-prod/providers/Microsoft.Network/virtualNetworks/vnet-monitoring-prod'
param flowLogStorageAccountId = '/subscriptions/YOUR-SUBSCRIPTION-ID/resourceGroups/rg-monitoring-prod/providers/Microsoft.Storage/storageAccounts/stflowprodXXXXXXXX'
param networkWatcherName = 'NetworkWatcher_norwayeast'
param networkWatcherResourceGroupName = 'NetworkWatcherRG'
param trafficAnalyticsInterval = 10

// Storage Account (globally unique — use subscription ID suffix)
param storageAccountName = 'stmonprodXXXXXXXX'    // ← replace suffix
param storageResourceGroupName = 'rg-storage-prod'

// Key Vault (globally unique — soft-delete reserves the name 90 days after deletion)
param keyVaultName = 'kv-mon-prod-XXXXXXXX'        // ← replace suffix
param keyVaultResourceGroupName = 'rg-kv-prod'

// ── Tags ──────────────────────────────────────────────────────────────────

param tags = {
  environment: 'prod'
  managedBy: 'bicep'
  solution: 'azure-monitoring'
  costCenter: 'platform'
}
