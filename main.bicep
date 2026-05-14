// Deploy to the monitoring resource group:
//   az deployment group create \
//     --resource-group rg-monitoring-dev \
//     --template-file main.bicep \
//     --parameters parameters/dev.bicepparam

targetScope = 'resourceGroup'

// ── Core ──────────────────────────────────────────────────────────────────

@description('Azure region for all monitoring resources')
param location string = 'norwayeast'

@allowed(['dev', 'prod'])
param environment string

@description('Log Analytics Workspace name')
param workspaceName string

@description('Application Insights name')
param appInsightsName string

@description('Data retention in days (30 dev / 90 prod)')
@minValue(30)
@maxValue(730)
param retentionInDays int

@description('Daily ingestion cap in GB (-1 = no cap)')
param dailyQuotaGb int = -1

// ── Action Group ──────────────────────────────────────────────────────────

@description('Short name in alert notifications (max 12 chars)')
@maxLength(12)
param actionGroupShortName string

@description('Email receivers: [{ name: string, emailAddress: string }]')
param emailReceivers array = []

@description('Webhook/Teams receivers: [{ name: string, serviceUri: string }]')
param webhookReceivers array = []

// ── Event Hub ─────────────────────────────────────────────────────────────

@description('Event Hub Namespace name')
param eventHubNamespaceName string

@description('Event Hub name for log export')
param eventHubName string

@allowed(['Basic', 'Standard', 'Premium'])
param eventHubSku string = 'Standard'

// ── Diagnostics — Front Door ──────────────────────────────────────────────

@description('Front Door profile name. Leave empty to skip this diag module.')
param frontDoorProfileName string = ''

@description('Resource group of the Front Door profile')
param frontDoorResourceGroupName string = resourceGroup().name

// ── Diagnostics — Container Apps ──────────────────────────────────────────

@description('Container Apps managed environment name. Leave empty to skip.')
param containerAppsEnvironmentName string = ''

@description('Resource group of the Container Apps environment')
param containerAppsResourceGroupName string = resourceGroup().name

// ── Diagnostics — NSG Flow Logs ───────────────────────────────────────────

@description('VNet name (used for flow log naming). Leave empty to skip.')
param vnetName string = ''

@description('Full ARM resource ID of the VNet, e.g. /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Network/virtualNetworks/{name}')
param vnetResourceId string = ''

@description('Storage Account resource ID for raw VNet flow log storage')
param flowLogStorageAccountId string = ''

@description('Network Watcher name for the deployment region')
param networkWatcherName string = 'NetworkWatcher_norwayeast'

@description('Resource group containing the Network Watcher (default: NetworkWatcherRG)')
param networkWatcherResourceGroupName string = 'NetworkWatcherRG'

@description('Traffic Analytics aggregation interval in minutes')
@allowed([10, 60])
param trafficAnalyticsInterval int = 10

// ── Diagnostics — Storage Account ─────────────────────────────────────────

@description('Storage account name. Leave empty to skip.')
param storageAccountName string = ''

@description('Resource group of the storage account')
param storageResourceGroupName string = resourceGroup().name

// ── Diagnostics — Key Vault ───────────────────────────────────────────────

@description('Key Vault name. Leave empty to skip.')
param keyVaultName string = ''

@description('Resource group of the Key Vault')
param keyVaultResourceGroupName string = resourceGroup().name

// ── Tags ──────────────────────────────────────────────────────────────────

param tags object = {
  environment: environment
  managedBy: 'bicep'
  solution: 'azure-monitoring'
}

// ════════════════════════════════════════════════════════════════════════════
// MONITORING MODULES — all deployed into the monitoring resource group
// ════════════════════════════════════════════════════════════════════════════

module logAnalytics './modules/monitoring/log-analytics.bicep' = {
  name: 'deploy-log-analytics'
  params: {
    location: location
    environment: environment
    workspaceName: workspaceName
    appInsightsName: appInsightsName
    retentionInDays: retentionInDays
    dailyQuotaGb: dailyQuotaGb
    tags: tags
  }
}

module actionGroups './modules/monitoring/action-groups.bicep' = {
  name: 'deploy-action-groups'
  params: {
    environment: environment
    actionGroupShortName: actionGroupShortName
    emailReceivers: emailReceivers
    webhookReceivers: webhookReceivers
    tags: tags
  }
}

module subscriptionDiag './modules/monitoring/subscription-diag.bicep' = {
  name: 'deploy-subscription-diag'
  scope: subscription()
  params: {
    workspaceId: logAnalytics.outputs.workspaceId
    environment: environment
  }
}

module alertRules './modules/monitoring/alert-rules.bicep' = {
  name: 'deploy-alert-rules'
  params: {
    location: location
    environment: environment
    workspaceId: logAnalytics.outputs.workspaceId
    actionGroupId: actionGroups.outputs.actionGroupId
    tags: tags
  }
}

module eventHubExport './modules/monitoring/eventhub-export.bicep' = {
  name: 'deploy-eventhub-export'
  params: {
    location: location
    environment: environment
    workspaceName: logAnalytics.outputs.workspaceName
    eventHubNamespaceName: eventHubNamespaceName
    eventHubName: eventHubName
    eventHubSku: eventHubSku
    tags: tags
  }
}

// ════════════════════════════════════════════════════════════════════════════
// DIAGNOSTIC MODULES — each deployed at the target resource's RG scope.
// Conditional: skipped when the resource name parameter is left empty.
// ════════════════════════════════════════════════════════════════════════════

// ── Front Door ────────────────────────────────────────────────────────────

module diagFrontDoor './modules/diag/diag-frontdoor.bicep' = if (!empty(frontDoorProfileName)) {
  name: 'deploy-diag-frontdoor'
  scope: resourceGroup(frontDoorResourceGroupName)
  params: {
    frontDoorProfileName: frontDoorProfileName
    workspaceId: logAnalytics.outputs.workspaceId
    eventHubAuthorizationRuleId: eventHubExport.outputs.eventHubAuthorizationRuleId
    eventHubName: eventHubName
  }
}

// ── Container Apps ────────────────────────────────────────────────────────

module diagContainerApps './modules/diag/diag-containerapps.bicep' = if (!empty(containerAppsEnvironmentName)) {
  name: 'deploy-diag-containerapps'
  scope: resourceGroup(containerAppsResourceGroupName)
  params: {
    containerAppsEnvironmentName: containerAppsEnvironmentName
    workspaceId: logAnalytics.outputs.workspaceId
    eventHubAuthorizationRuleId: eventHubExport.outputs.eventHubAuthorizationRuleId
    eventHubName: eventHubName
  }
}

// ── VNet Flow Logs (deployed at NetworkWatcherRG scope) ──────────────────

module diagVnet './modules/diag/diag-vnet.bicep' = if (!empty(vnetName) && !empty(vnetResourceId) && !empty(flowLogStorageAccountId)) {
  name: 'deploy-diag-vnet'
  scope: resourceGroup(networkWatcherResourceGroupName)
  params: {
    location: location
    environment: environment
    networkWatcherName: networkWatcherName
    vnetName: vnetName
    vnetResourceId: vnetResourceId
    flowLogStorageAccountId: flowLogStorageAccountId
    workspaceId: logAnalytics.outputs.workspaceId
    workspaceCustomerId: logAnalytics.outputs.workspaceCustomerId
    workspaceLocation: location
    trafficAnalyticsInterval: trafficAnalyticsInterval
    retentionDays: min(retentionInDays, 365)
    tags: tags
  }
}

// ── Storage Account ───────────────────────────────────────────────────────

module diagStorage './modules/diag/diag-storage.bicep' = if (!empty(storageAccountName)) {
  name: 'deploy-diag-storage'
  scope: resourceGroup(storageResourceGroupName)
  params: {
    storageAccountName: storageAccountName
    workspaceId: logAnalytics.outputs.workspaceId
    eventHubAuthorizationRuleId: eventHubExport.outputs.eventHubAuthorizationRuleId
    eventHubName: eventHubName
  }
}

// ── Key Vault ─────────────────────────────────────────────────────────────

module diagKeyVault './modules/diag/diag-keyvault.bicep' = if (!empty(keyVaultName)) {
  name: 'deploy-diag-keyvault'
  scope: resourceGroup(keyVaultResourceGroupName)
  params: {
    keyVaultName: keyVaultName
    workspaceId: logAnalytics.outputs.workspaceId
    eventHubAuthorizationRuleId: eventHubExport.outputs.eventHubAuthorizationRuleId
    eventHubName: eventHubName
  }
}

// ════════════════════════════════════════════════════════════════════════════
// OUTPUTS
// ════════════════════════════════════════════════════════════════════════════

output workspaceId string = logAnalytics.outputs.workspaceId
output workspaceName string = logAnalytics.outputs.workspaceName
output appInsightsConnectionString string = logAnalytics.outputs.appInsightsConnectionString
output actionGroupId string = actionGroups.outputs.actionGroupId
output eventHubNamespaceName string = eventHubExport.outputs.eventHubNamespaceName
output eventHubAuthorizationRuleId string = eventHubExport.outputs.eventHubAuthorizationRuleId
