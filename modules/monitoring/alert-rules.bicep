@description('Log Analytics Workspace resource ID — all KQL alerts target this scope')
param workspaceId string

@description('Action Group resource ID to notify on alert fire/resolve')
param actionGroupId string

@description('Azure region — required for scheduledQueryRules resources')
param location string

@description('Environment name used in display names and resource names')
param environment string

param tags object = {}

// ── Scheduled Query Rules (KQL-based log alerts) ──────────────────────────
//
// Pattern used throughout:
//   - Query returns rows only when the condition is violated
//   - timeAggregation: 'Count' counts returned rows
//   - threshold: 0 + operator: 'GreaterThan' fires when any rows exist
//   - windowSize covers the ago() range used in the KQL
//   - evaluationFrequency = how often Azure re-runs the query
//   - autoMitigate: true = alert auto-resolves when next evaluation returns 0 rows
//   - severity 0=Critical, 1=Error, 2=Warning, 3=Informational

// ── Container Apps: error spike ───────────────────────────────────────────

resource alertContainerAppErrors 'Microsoft.Insights/scheduledQueryRules@2022-06-15' = {
  name: 'alert-containerapps-errors-${environment}'
  location: location
  tags: tags
  kind: 'LogAlert'
  properties: {
    displayName: '[${toUpper(environment)}] Container Apps — Error spike (>10 in 5 min)'
    description: 'Console logs contain more than 10 Error/Exception lines in a 5-minute window'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT10M'
    scopes: [workspaceId]
    criteria: {
      allOf: [
        {
          query: '''
ContainerAppConsoleLogs
| where TimeGenerated > ago(10m)
| where Log has_any ("Error", "Exception", "FATAL", "Unhandled")
| summarize ErrorCount = count() by ContainerAppName, bin(TimeGenerated, 5m)
| where ErrorCount > 10
'''
          timeAggregation: 'Count'
          threshold: 0
          operator: 'GreaterThan'
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroupId]
    }
    autoMitigate: true
  }
}

// ── Key Vault: throttling (HTTP 429) ──────────────────────────────────────

resource alertKeyVaultThrottling 'Microsoft.Insights/scheduledQueryRules@2022-06-15' = {
  name: 'alert-keyvault-throttling-${environment}'
  location: location
  tags: tags
  kind: 'LogAlert'
  properties: {
    displayName: '[${toUpper(environment)}] Key Vault — Throttling (HTTP 429)'
    description: 'Key Vault is returning 429 Too Many Requests — client is being rate-limited'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    scopes: [workspaceId]
    criteria: {
      allOf: [
        {
          query: '''
AzureDiagnostics
| where TimeGenerated > ago(15m)
| where ResourceProvider == "MICROSOFT.KEYVAULT"
| where httpStatusCode_d == 429.0
| summarize ThrottleCount = count() by Resource, bin(TimeGenerated, 5m)
| where ThrottleCount > 5
'''
          timeAggregation: 'Count'
          threshold: 0
          operator: 'GreaterThan'
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroupId]
    }
    autoMitigate: true
  }
}

// ── Front Door: 5xx server-side error spike ───────────────────────────────
// Targets AFD Standard/Premium (Microsoft.Cdn/profiles).
// The access log category is "FrontDoorAccessLog" in AzureDiagnostics.

resource alertFrontDoor5xx 'Microsoft.Insights/scheduledQueryRules@2022-06-15' = {
  name: 'alert-frontdoor-5xx-${environment}'
  location: location
  tags: tags
  kind: 'LogAlert'
  properties: {
    displayName: '[${toUpper(environment)}] Front Door — 5xx error spike (>20 in 5 min)'
    description: 'Azure Front Door is returning more than 20 server-side errors in a 5-minute window'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT10M'
    scopes: [workspaceId]
    criteria: {
      allOf: [
        {
          query: '''
AzureDiagnostics
| where TimeGenerated > ago(10m)
| where ResourceProvider == "MICROSOFT.CDN"
| where Category == "FrontDoorAccessLog"
| where httpStatusCode_d >= 500 and httpStatusCode_d < 600
| summarize ErrorCount = count() by bin(TimeGenerated, 5m)
| where ErrorCount > 20
'''
          timeAggregation: 'Count'
          threshold: 0
          operator: 'GreaterThan'
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroupId]
    }
    autoMitigate: true
  }
}

// ── Storage Account: server-side error rate ────────────────────────────────

resource alertStorageErrors 'Microsoft.Insights/scheduledQueryRules@2022-06-15' = {
  name: 'alert-storage-errors-${environment}'
  location: location
  tags: tags
  kind: 'LogAlert'
  properties: {
    displayName: '[${toUpper(environment)}] Storage Account — Server errors (5xx)'
    description: 'Storage blob service is returning HTTP 5xx errors, indicating service-side issues'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT15M'
    windowSize: 'PT30M'
    scopes: [workspaceId]
    criteria: {
      allOf: [
        {
          query: '''
StorageBlobLogs
| where TimeGenerated > ago(30m)
| where toint(StatusCode) >= 500
| summarize ErrorCount = count() by AccountName, bin(TimeGenerated, 15m)
| where ErrorCount > 10
'''
          timeAggregation: 'Count'
          threshold: 0
          operator: 'GreaterThan'
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroupId]
    }
    autoMitigate: true
  }
}

// ── Key Vault: approaching soft-delete expiry ──────────────────────────────
// Fires when a secret deletion event is logged — useful for compliance audits

resource alertKeyVaultDeletion 'Microsoft.Insights/scheduledQueryRules@2022-06-15' = {
  name: 'alert-keyvault-secret-deleted-${environment}'
  location: location
  tags: tags
  kind: 'LogAlert'
  properties: {
    displayName: '[${toUpper(environment)}] Key Vault — Secret/Key deleted'
    description: 'A secret or key was deleted in Key Vault — verify this is intentional'
    severity: 3
    enabled: true
    evaluationFrequency: 'PT15M'
    windowSize: 'PT15M'
    scopes: [workspaceId]
    criteria: {
      allOf: [
        {
          query: '''
AzureDiagnostics
| where TimeGenerated > ago(15m)
| where ResourceProvider == "MICROSOFT.KEYVAULT"
| where OperationName has_any ("SecretDelete", "KeyDelete", "CertificateDelete")
| project TimeGenerated, Resource, OperationName, CallerIPAddress, ResultType, requestUri_s
'''
          timeAggregation: 'Count'
          threshold: 0
          operator: 'GreaterThan'
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroupId]
    }
    autoMitigate: false
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────

output alertRuleIds array = [
  alertContainerAppErrors.id
  alertKeyVaultThrottling.id
  alertFrontDoor5xx.id
  alertStorageErrors.id
  alertKeyVaultDeletion.id
]
