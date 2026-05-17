using '../main.bicep'

// ── Core ──────────────────────────────────────────────────────────────────

param location = 'norwayeast'
param environment = 'dev'
param workspaceName = 'law-monitoring-dev'
param appInsightsName = 'appi-monitoring-dev'
param retentionInDays = 30
param dailyQuotaGb = 5

// ── Action Group ──────────────────────────────────────────────────────────

param actionGroupShortName = 'mon-dev'

param emailReceivers = [
  {
    name: 'OpsTeam'
    emailAddress: 'YOUR-OPS-EMAIL@contoso.com'  // ← replace
  }
]

// Teams webhook: same Power Automate flow URL as prod can be reused
param webhookReceivers = [
  {
    name: 'TeamsOpsChannel'
    serviceUri: 'YOUR-POWER-AUTOMATE-URL'       // ← replace (see DEPLOY.md Step 7)
  }
]

// ── Event Hub ─────────────────────────────────────────────────────────────
// Namespace names are globally unique in Azure.
// Use the first 8 characters of your subscription ID as a suffix.

param eventHubNamespaceName = 'evhns-mon-dev-XXXXXXXX'  // ← replace suffix
param eventHubName = 'evh-monitoring-dev'
param eventHubSku = 'Standard'

// ── Diagnostics ───────────────────────────────────────────────────────────
// Leave a field empty ('') to skip that module.
// Fill in and redeploy once the resource exists in Azure.

// Front Door
param frontDoorProfileName = 'afd-monitoring-dev'
param frontDoorResourceGroupName = 'rg-monitoring-dev'

// Container Apps
param containerAppsEnvironmentName = 'cae-monitoring-dev'
param containerAppsResourceGroupName = 'rg-monitoring-dev'

// VNet Flow Logs
// Get VNet ID:      az network vnet show -g rg-network-dev -n vnet-monitoring-dev --query id -o tsv
// Get storage ID:   az storage account show -g rg-monitoring-dev -n stflowdevXXXXXXXX --query id -o tsv
param vnetName = 'vnet-monitoring-dev'
param vnetResourceId = '/subscriptions/YOUR-SUBSCRIPTION-ID/resourceGroups/rg-network-dev/providers/Microsoft.Network/virtualNetworks/vnet-monitoring-dev'
param flowLogStorageAccountId = '/subscriptions/YOUR-SUBSCRIPTION-ID/resourceGroups/rg-monitoring-dev/providers/Microsoft.Storage/storageAccounts/stflowdevXXXXXXXX'
param networkWatcherName = 'NetworkWatcher_norwayeast'
param networkWatcherResourceGroupName = 'NetworkWatcherRG'
param trafficAnalyticsInterval = 10

// Storage Account (globally unique — use subscription ID suffix)
param storageAccountName = 'stmondevXXXXXXXX'   // ← replace suffix
param storageResourceGroupName = 'rg-storage-dev'

// Key Vault (globally unique — soft-delete reserves the name 90 days after deletion)
param keyVaultName = 'kv-mon-dev-XXXXXXXX'       // ← replace suffix
param keyVaultResourceGroupName = 'rg-kv-dev'

// ── Tags ──────────────────────────────────────────────────────────────────

param tags = {
  environment: 'dev'
  managedBy: 'bicep'
  solution: 'azure-monitoring'
  costCenter: 'platform'
}
