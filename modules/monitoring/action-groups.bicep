@description('Environment suffix used in the action group name')
param environment string

@description('Short name shown in alert emails and SMS (max 12 chars)')
@maxLength(12)
param actionGroupShortName string

@description('Email receivers. Each item: { name, emailAddress }')
param emailReceivers array = []

@description('Webhook/Teams receivers. Each item: { name, serviceUri }')
param webhookReceivers array = []

param tags object = {}

// ── Action Group ──────────────────────────────────────────────────────────
// Action groups are always global — location is irrelevant for routing.
// Common Alert Schema normalises the payload across all alert types so the
// webhook receiver (e.g. Power Automate → Teams) can parse a single schema.

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-monitoring-${environment}'
  location: 'global'
  tags: tags
  properties: {
    enabled: true
    groupShortName: actionGroupShortName
    emailReceivers: [for r in emailReceivers: {
      name: r.name
      emailAddress: r.emailAddress
      useCommonAlertSchema: true
    }]
    webhookReceivers: [for r in webhookReceivers: {
      name: r.name
      serviceUri: r.serviceUri
      useCommonAlertSchema: true
      // useAadAuth = false → standard HTTPS POST; set to true + configure
      // managed identity if the endpoint requires Azure AD authentication
      useAadAuth: false
    }]
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────

output actionGroupId string = actionGroup.id
output actionGroupName string = actionGroup.name
