// ── Deployment scope note ─────────────────────────────────────────────────
// This module must be called from main.bicep with:
//   scope: resourceGroup(<frontDoorResourceGroupName>)
// That puts the deployment — and therefore all resources in this file —
// into the Front Door's resource group, satisfying Bicep's scope constraint.

@description('Name of the Front Door Standard/Premium profile (Microsoft.Cdn/profiles)')
param frontDoorProfileName string

@description('Log Analytics Workspace resource ID — destination for all log categories')
param workspaceId string

@description('Event Hub authorization rule resource ID for SIEM streaming (leave empty to skip)')
param eventHubAuthorizationRuleId string = ''

@description('Event Hub name for streaming (required when eventHubAuthorizationRuleId is set)')
param eventHubName string = ''

// ── Existing resource reference ───────────────────────────────────────────
// No explicit scope here — the module is already deployed into the correct
// resource group via the scope property on the module call in main.bicep.

resource frontDoor 'Microsoft.Cdn/profiles@2023-05-01' existing = {
  name: frontDoorProfileName
}

// ── Diagnostic Settings ───────────────────────────────────────────────────
// scope: frontDoor registers the diagnostic settings as an ARM extension
// resource on the Front Door profile (/providers/microsoft.insights/diagnosticsettings/...).

resource diagSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-law'
  scope: frontDoor
  properties: {
    workspaceId: workspaceId
    eventHubAuthorizationRuleId: !empty(eventHubAuthorizationRuleId) ? eventHubAuthorizationRuleId : null
    eventHubName: !empty(eventHubName) ? eventHubName : null
    logs: [
      {
        // All HTTP access requests: method, URL, status, latency, POP, client IP
        category: 'FrontDoorAccessLog'
        enabled: true
      }
      {
        // Health probe results per origin — shows which backends are degraded
        category: 'FrontDoorHealthProbeLog'
        enabled: true
      }
      {
        // WAF rule matches and blocks — critical for security visibility
        category: 'FrontDoorWebApplicationFirewallLog'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────

output diagnosticSettingId string = diagSettings.id
