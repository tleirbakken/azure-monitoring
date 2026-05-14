// ── Deployment scope note ─────────────────────────────────────────────────
// Call from main.bicep with:
//   scope: resourceGroup(<networkWatcherResourceGroupName>)
//
// NSG flow logs were retired June 30, 2025 — new creation is blocked.
// This module uses VNet flow logs, the recommended replacement.
// VNet resource ID is passed as a string to avoid Bicep cross-scope issues.

@description('Azure region — must match the VNet and Network Watcher region')
param location string

@description('Name of the Network Watcher for this region (auto-created by Azure)')
param networkWatcherName string = 'NetworkWatcher_norwayeast'

@description('VNet name — used only for naming the flow log resource')
param vnetName string

@description('Full ARM resource ID of the VNet, e.g. /subscriptions/.../virtualNetworks/vnet-name')
param vnetResourceId string

@description('Storage Account resource ID for raw flow log JSON (required by ARM even when Traffic Analytics is enabled)')
param flowLogStorageAccountId string

@description('Log Analytics Workspace resource ID for Traffic Analytics')
param workspaceId string

@description('Log Analytics Workspace GUID (customerId) — NOT the ARM resource ID. Output from log-analytics module.')
param workspaceCustomerId string

@description('Azure region of the Log Analytics Workspace')
param workspaceLocation string

@description('Raw flow log retention in days in the storage account')
@minValue(1)
@maxValue(365)
param retentionDays int = 30

@description('Traffic Analytics aggregation interval in minutes. 10 min = near-real-time, 60 min = lower cost.')
@allowed([10, 60])
param trafficAnalyticsInterval int = 10

@description('Environment suffix for resource naming')
param environment string

param tags object = {}

// ── Existing Network Watcher ──────────────────────────────────────────────

resource networkWatcher 'Microsoft.Network/networkWatchers@2023-06-01' existing = {
  name: networkWatcherName
}

// ── VNet Flow Log ─────────────────────────────────────────────────────────
// Replaces NSG flow logs (retired June 2025).
// targetResourceId points to the VNet — captures all traffic on all subnets.
// vnetResourceId is a string parameter → no Bicep cross-scope constraint.

resource flowLog 'Microsoft.Network/networkWatchers/flowLogs@2024-01-01' = {
  parent: networkWatcher
  name: 'flowlog-${vnetName}-${environment}'
  location: location
  tags: tags
  properties: {
    targetResourceId: vnetResourceId
    storageId: flowLogStorageAccountId
    enabled: true
    format: {
      type: 'JSON'
      version: 2
    }
    flowAnalyticsConfiguration: {
      networkWatcherFlowAnalyticsConfiguration: {
        enabled: true
        workspaceId: workspaceCustomerId
        workspaceRegion: workspaceLocation
        workspaceResourceId: workspaceId
        trafficAnalyticsInterval: trafficAnalyticsInterval
      }
    }
    retentionPolicy: {
      days: retentionDays
      enabled: true
    }
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────

output flowLogId string = flowLog.id
output flowLogName string = flowLog.name
