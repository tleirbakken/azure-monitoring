// ── Deployment scope note ─────────────────────────────────────────────────
// Call from main.bicep with:
//   scope: resourceGroup(<storageResourceGroupName>)

@description('Storage account name')
param storageAccountName string

@description('Log Analytics Workspace resource ID')
param workspaceId string

@description('Event Hub authorization rule resource ID for SIEM streaming (leave empty to skip)')
param eventHubAuthorizationRuleId string = ''

@description('Event Hub name for streaming (required when eventHubAuthorizationRuleId is set)')
param eventHubName string = ''

// ── Existing resource references ──────────────────────────────────────────
// Diagnostic settings for storage are split across the account and each
// service endpoint (blob, table, queue, file) — they are separate ARM resources.

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' existing = {
  parent: storageAccount
  name: 'default'
}

// ── Storage Account — metrics only ───────────────────────────────────────
// The account-level resource has no useful log categories; only metrics.
// Transaction and Capacity metrics give an availability and usage overview.

resource diagStorageAccount 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-law'
  scope: storageAccount
  properties: {
    workspaceId: workspaceId
    eventHubAuthorizationRuleId: !empty(eventHubAuthorizationRuleId) ? eventHubAuthorizationRuleId : null
    eventHubName: !empty(eventHubName) ? eventHubName : null
    metrics: [
      {
        // Aggregated counts of requests and errors per transaction type
        category: 'Transaction'
        enabled: true
      }
    ]
  }
}

// ── Blob Service — logs + metrics ─────────────────────────────────────────
// StorageBlobLogs table in LAW receives every authenticated blob operation.
// This is the most valuable surface for monitoring data exfiltration,
// misconfigured public access, and application-level blob errors.

resource diagBlobService 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-law'
  scope: blobService
  properties: {
    workspaceId: workspaceId
    eventHubAuthorizationRuleId: !empty(eventHubAuthorizationRuleId) ? eventHubAuthorizationRuleId : null
    eventHubName: !empty(eventHubName) ? eventHubName : null
    logs: [
      {
        // GET, HEAD, GET ACL — every read operation with caller IP and auth method
        category: 'StorageRead'
        enabled: true
      }
      {
        // PUT, POST, COPY, SET ACL — write operations
        category: 'StorageWrite'
        enabled: true
      }
      {
        // DELETE, Undelete — deletion audit trail
        category: 'StorageDelete'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'Transaction'
        enabled: true
      }
    ]
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────

output storageAccountDiagId string = diagStorageAccount.id
output blobServiceDiagId string = diagBlobService.id
