// ── Deployment scope note ─────────────────────────────────────────────────
// Call from main.bicep with:
//   scope: resourceGroup(<keyVaultResourceGroupName>)

@description('Key Vault name')
param keyVaultName string

@description('Log Analytics Workspace resource ID')
param workspaceId string

@description('Event Hub authorization rule resource ID for SIEM streaming (leave empty to skip)')
param eventHubAuthorizationRuleId string = ''

@description('Event Hub name for streaming (required when eventHubAuthorizationRuleId is set)')
param eventHubName string = ''

// ── Existing resource reference ───────────────────────────────────────────

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// ── Diagnostic Settings ───────────────────────────────────────────────────
// AuditEvent is the single most important category for Key Vault:
// every secret get/set/delete, certificate operation, and access denial
// is written here — essential for compliance and security investigations.

resource diagSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-law'
  scope: keyVault
  properties: {
    workspaceId: workspaceId
    eventHubAuthorizationRuleId: !empty(eventHubAuthorizationRuleId) ? eventHubAuthorizationRuleId : null
    eventHubName: !empty(eventHubName) ? eventHubName : null
    logs: [
      {
        // Full access audit: who read/wrote/deleted which secret, from which IP, with which identity
        category: 'AuditEvent'
        enabled: true
      }
      {
        // Azure Policy evaluation results against the vault — useful for compliance posture
        category: 'AzurePolicyEvaluationDetails'
        enabled: true
      }
    ]
    metrics: [
      {
        // ServiceApiHit, ServiceApiLatency, ServiceApiResult — vault availability and latency
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────

output diagnosticSettingId string = diagSettings.id
