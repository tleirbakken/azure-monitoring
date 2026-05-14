@description('Azure region for all resources')
param location string

@description('Environment name — controls sampling rate and naming')
@allowed(['dev', 'prod'])
param environment string

@description('Name of the Log Analytics Workspace')
param workspaceName string

@description('Name of the Application Insights instance')
param appInsightsName string

@description('Data retention in days (30–730)')
@minValue(30)
@maxValue(730)
param retentionInDays int

@description('Daily ingestion cap in GB. Use -1 for no cap.')
param dailyQuotaGb int = -1

param tags object = {}

// ── Log Analytics Workspace ────────────────────────────────────────────────

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    workspaceCapping: {
      dailyQuotaGb: dailyQuotaGb
    }
    features: {
      // Restricts log access to the resource's own resource group — avoids cross-tenant leakage
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ── Application Insights (workspace-based, not classic) ───────────────────

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    RetentionInDays: retentionInDays
    // 50 % sampling in dev keeps costs down without losing signal; prod captures everything
    SamplingPercentage: environment == 'dev' ? 50 : 100
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────

output workspaceId string = logAnalyticsWorkspace.id
output workspaceName string = logAnalyticsWorkspace.name

// customerId is the GUID used by NSG Flow Logs / Traffic Analytics (not the full ARM resource ID)
output workspaceCustomerId string = logAnalyticsWorkspace.properties.customerId

output appInsightsId string = appInsights.id

@description('Prefer connectionString over instrumentationKey for new SDK versions')
output appInsightsConnectionString string = appInsights.properties.ConnectionString

output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
