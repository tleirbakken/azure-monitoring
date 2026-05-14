targetScope = 'subscription'

@description('Log Analytics Workspace resource ID — activity logs sendes hit')
param workspaceId string

@description('Environment name — brukes i ressursnavnet')
param environment string

resource activityLogDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'activity-to-law-${environment}'
  properties: {
    workspaceId: workspaceId
    logs: [
      { category: 'Administrative',  enabled: true }
      { category: 'Security',        enabled: true }
      { category: 'ServiceHealth',   enabled: true }
      { category: 'Alert',           enabled: true }
      { category: 'Recommendation',  enabled: true }
      { category: 'Policy',          enabled: true }
      { category: 'Autoscale',       enabled: true }
      { category: 'ResourceHealth',  enabled: true }
    ]
  }
}

output diagnosticSettingName string = activityLogDiag.name
