@description('Azure region')
param location string

@description('Environment name')
param environment string

@description('Log Analytics Workspace name — needed to scope the data export child resource')
param workspaceName string

@description('Event Hub Namespace name')
param eventHubNamespaceName string

@description('Name of the Event Hub that receives the exported log tables')
param eventHubName string

@description('Event Hub Namespace SKU. Standard supports 1 consumer group; Premium adds partitions and schema registry.')
@allowed(['Basic', 'Standard', 'Premium'])
param eventHubSku string = 'Standard'

@description('Message retention in days (Basic: max 1, Standard/Premium: max 7)')
@minValue(1)
@maxValue(7)
param messageRetentionDays int = 1

@description('Partition count — higher value allows more parallel SIEM consumers')
@minValue(1)
@maxValue(32)
param partitionCount int = 4

param tags object = {}

// ── Event Hub Namespace ───────────────────────────────────────────────────

resource eventHubNamespace 'Microsoft.EventHub/namespaces@2023-01-01-preview' = {
  name: eventHubNamespaceName
  location: location
  tags: tags
  sku: {
    name: eventHubSku
    tier: eventHubSku
    capacity: 1
  }
  properties: {
    isAutoInflateEnabled: false
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    zoneRedundant: false
  }
}

// ── Event Hub ─────────────────────────────────────────────────────────────

resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2023-01-01-preview' = {
  parent: eventHubNamespace
  name: eventHubName
  properties: {
    messageRetentionInDays: messageRetentionDays
    partitionCount: partitionCount
    status: 'Active'
  }
}

// ── Authorization Rule ────────────────────────────────────────────────────
// Azure Monitor uses this rule to authenticate when streaming data from LAW.
// Manage + Send + Listen covers the export service and SIEM consumers.

resource authRule 'Microsoft.EventHub/namespaces/authorizationRules@2023-01-01-preview' = {
  parent: eventHubNamespace
  name: 'MonitorExport'
  properties: {
    rights: ['Manage', 'Send', 'Listen']
  }
}

// ── Consumer Group for SIEM ───────────────────────────────────────────────
// A dedicated consumer group prevents the SIEM reader from competing with
// other downstream consumers (e.g. Azure Stream Analytics, Sentinel).

resource siemConsumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2023-01-01-preview' = {
  parent: eventHub
  name: 'siem-consumer'
  properties: {}
}

// ── Log Analytics Data Export Rule ───────────────────────────────────────
// Continuously exports selected tables from the workspace to the Event Hub
// namespace. Only tables that already exist in the workspace are exported.
// If a table listed here is not yet populated, it is silently ignored.
// Supported tables: https://learn.microsoft.com/azure/azure-monitor/logs/logs-data-export?tabs=portal#supported-tables

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource dataExport 'Microsoft.OperationalInsights/workspaces/dataExports@2020-08-01' = {
  parent: workspace
  name: 'export-to-eventhub-${environment}'
  properties: {
    destination: {
      resourceId: eventHubNamespace.id
      metaData: {
        // Without eventHubName the export creates one hub per table.
        // Specify it to funnel all tables into a single hub.
        eventHubName: eventHubName
      }
    }
    tableNames: [
      'AzureActivity'
      'AzureDiagnostics'
      'AzureMetrics'
      'StorageBlobLogs'
      'ContainerAppConsoleLogs'
      'ContainerAppSystemLogs'
    ]
    enable: true
  }
  // Explicit dependency: the namespace and hub must exist before the export
  // rule is created, even though the destination is referenced by resource ID.
  dependsOn: [eventHub]
}

// ── Outputs ───────────────────────────────────────────────────────────────

output eventHubNamespaceId string = eventHubNamespace.id
output eventHubNamespaceName string = eventHubNamespace.name
output eventHubId string = eventHub.id

// Output the auth rule resource ID — callers retrieve the connection string at runtime
// via listKeys() or by storing it in Key Vault after deployment.
output eventHubAuthorizationRuleId string = authRule.id
