// ── Deployment scope note ─────────────────────────────────────────────────
// Call from main.bicep with:
//   scope: resourceGroup(<containerAppsResourceGroupName>)

@description('Name of the Container Apps managed environment (Microsoft.App/managedEnvironments)')
param containerAppsEnvironmentName string

@description('Log Analytics Workspace resource ID')
param workspaceId string

@description('Event Hub authorization rule resource ID for SIEM streaming (leave empty to skip)')
param eventHubAuthorizationRuleId string = ''

@description('Event Hub name for streaming (required when eventHubAuthorizationRuleId is set)')
param eventHubName string = ''

// ── Existing resource reference ───────────────────────────────────────────

resource containerAppsEnv 'Microsoft.App/managedEnvironments@2023-05-01' existing = {
  name: containerAppsEnvironmentName
}

// ── Diagnostic Settings ───────────────────────────────────────────────────
// Container Apps environments funnel all app logs through the managed
// environment — configuring diagnostics here captures every app in the env.

resource diagSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-law'
  scope: containerAppsEnv
  properties: {
    workspaceId: workspaceId
    eventHubAuthorizationRuleId: !empty(eventHubAuthorizationRuleId) ? eventHubAuthorizationRuleId : null
    eventHubName: !empty(eventHubName) ? eventHubName : null
    logs: [
      {
        // stdout/stderr from every container replica — matches ContainerAppConsoleLogs table in LAW
        category: 'ContainerAppConsoleLogs'
        enabled: true
      }
      {
        // Platform events: replica starts, stops, crashes, scaling decisions
        category: 'ContainerAppSystemLogs'
        enabled: true
      }
    ]
    // Managed environments do not expose metrics via diagnostic settings;
    // metrics are available natively in Azure Monitor Metrics.
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────

output diagnosticSettingId string = diagSettings.id
