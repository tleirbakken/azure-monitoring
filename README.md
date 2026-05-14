# Azure Monitor — Solution Documentation

## Table of Contents

1. [Purpose and Scope](#purpose-and-scope)
2. [Architecture](#architecture)
3. [File Structure](#file-structure)
4. [Monitoring Modules](#monitoring-modules)
   - [log-analytics.bicep](#log-analyticsbicep)
   - [action-groups.bicep](#action-groupsbicep)
   - [alert-rules.bicep](#alert-rulesbicep)
   - [eventhub-export.bicep](#eventhub-exportbicep)
5. [Diagnostic Modules](#diagnostic-modules)
   - [diag-frontdoor.bicep](#diag-frontdoorbicep)
   - [diag-containerapps.bicep](#diag-containerappsbicep)
   - [diag-vnet.bicep](#diag-vnetbicep)
   - [diag-storage.bicep](#diag-storagebicep)
   - [diag-keyvault.bicep](#diag-keyvaultbicep)
6. [Orchestrator — main.bicep](#orchestrator--mainbicep)
7. [Parameter Files](#parameter-files)
8. [Design Decisions](#design-decisions)
9. [Alert Rules — KQL Reference](#alert-rules--kql-reference)
10. [Deployment](#deployment)
11. [Next Steps](#next-steps)

---

## Purpose and Scope

The solution sets up centralised monitoring in Azure for the following resources:

| Resource | Type |
|---------|------|
| Azure Front Door | Standard/Premium (`Microsoft.Cdn/profiles`) |
| Azure Container Apps | Managed Environment (`Microsoft.App/managedEnvironments`) |
| Azure VNet | VNet Flow Logs with Traffic Analytics |
| Storage Accounts | Blob service with full operation logging |
| Key Vaults | Complete access auditing |

Everything is written in **Bicep** and deployed via Azure CLI. The solution is split into two environments: `dev` and `prod`, with separate parameter files.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  rg-monitoring-dev / rg-monitoring-prod                         │
│                                                                  │
│  ┌──────────────────────┐   ┌──────────────────────────────┐    │
│  │  Log Analytics       │   │  Application Insights        │    │
│  │  Workspace (LAW)     │◄──│  (workspace-based)           │    │
│  │                      │   └──────────────────────────────┘    │
│  │  - Alerts (KQL)      │   ┌──────────────────────────────┐    │
│  │  - Traffic Analytics │   │  Action Group                │    │
│  │  - Data Export       │──►│  - Email                     │    │
│  └──────────┬───────────┘   │  - Teams / Webhook           │    │
│             │               └──────────────────────────────┘    │
│             │               ┌──────────────────────────────┐    │
│             └──────────────►│  Event Hub Namespace          │    │
│                             │  - Data Export (LAW → EH)    │    │
│                             │  - SIEM Consumer Group       │    │
│                             └──────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
         ▲ Diagnostic settings pushed HERE from other RGs
         │
┌────────┴────────────────────────────────────────────────────────┐
│  Other resource groups (dev / prod)                             │
│                                                                  │
│  rg-frontend   → Front Door  ──► Diagnostic Settings ──► LAW   │
│  rg-apps       → Container Apps ► Diagnostic Settings ──► LAW   │
│  rg-storage    → Storage Account► Diagnostic Settings ──► LAW   │
│  rg-security   → Key Vault ────► Diagnostic Settings ──► LAW   │
│  NetworkWatcherRG → VNet Flow Logs ──────────────────────► LAW  │
└─────────────────────────────────────────────────────────────────┘
```

**Centralised LAW model:** All resources send logs to a single Log Analytics Workspace. This provides one place to search, write KQL queries, and configure alerts across the entire platform.

---

## File Structure

```
azure-monitoring/
├── main.bicep                          ← Orchestrator, wires all modules together
├── bicepconfig.json                    ← Linter rules for code validation
├── README.md                           ← This file
├── .gitignore
│
├── modules/
│   ├── monitoring/                     ← Resources always deployed
│   │   ├── log-analytics.bicep         ← LAW + App Insights
│   │   ├── action-groups.bicep         ← Notification channels (email, Teams)
│   │   ├── alert-rules.bicep           ← KQL-based alert rules
│   │   ├── eventhub-export.bicep       ← Event Hub for SIEM integration
│   │   └── subscription-diag.bicep     ← Subscription Activity Log → LAW
│   │
│   └── diag/                           ← Diagnostic settings per resource type
│       ├── diag-frontdoor.bicep
│       ├── diag-containerapps.bicep
│       ├── diag-vnet.bicep             ← VNet Flow Logs + Traffic Analytics
│       ├── diag-storage.bicep
│       └── diag-keyvault.bicep
│
├── parameters/
│   ├── dev.bicepparam                  ← Values for dev environment
│   └── prod.bicepparam                 ← Values for prod environment
│
└── scripts/
    ├── deploy.ps1
    └── validate.ps1
```

---

## Monitoring Modules

### log-analytics.bicep

**File:** `modules/monitoring/log-analytics.bicep`

#### Resources Created

| Resource | ARM Type | Name (dev/prod) |
|---------|----------|-----------------|
| Log Analytics Workspace | `Microsoft.OperationalInsights/workspaces` | `law-monitoring-dev` / `law-monitoring-prod` |
| Application Insights | `Microsoft.Insights/components` | `appi-monitoring-dev` / `appi-monitoring-prod` |

#### Configuration and Rationale

**Log Analytics Workspace**

```
SKU: PerGB2018
```
`PerGB2018` is the only SKU that supports all modern Azure Monitor features, including Traffic Analytics, data export, and workspace-based App Insights. It bills per GB of ingested data.

```
retentionInDays: 30 (dev) / 90 (prod)
```
Shorter retention in dev keeps costs down. 90 days in prod provides enough history for trend analysis and incident investigations without runaway costs.

```
dailyQuotaGb: 5 (dev) / 10 (prod)
```
The daily cap prevents a misconfigured resource from sending enormous amounts of data and generating an unexpected bill. The cap triggers an alert in the Azure portal and stops ingestion for the rest of the day. Set to `-1` for no cap.

```
enableLogAccessUsingOnlyResourcePermissions: true
```
Without this, anyone with read access to the workspace can see logs from *all* resources sending to it. With this setting, users only see logs from resources they already have access to. Important for multi-team environments.

**Application Insights**

```
IngestionMode: LogAnalytics
```
This is "workspace-based" App Insights — the modern variant. Data is stored directly in the LAW database, not in a separate classic App Insights database. This means you can write KQL queries that combine App Insights data with other logs in the same workspace.

```
SamplingPercentage: 50 (dev) / 100 (prod)
```
In dev, 50% sampling reduces costs without losing important signal. In prod, we collect everything for full traceability.

#### Module Outputs

| Output | Used by |
|--------|-----------|
| `workspaceId` | All other modules that need a workspace reference |
| `workspaceName` | `eventhub-export.bicep` (for data export child resource) |
| `workspaceCustomerId` | `diag-vnet.bicep` — Traffic Analytics requires the workspace GUID, not the ARM resource ID |
| `appInsightsConnectionString` | Applications instrumented with the App Insights SDK |
| `appInsightsInstrumentationKey` | Older SDKs (prefer `connectionString` for new ones) |

> **Note:** The Traffic Analytics solution (`OMSGallery/TrafficAnalytics`) is **no longer** installed via Bicep. Microsoft blocked creation of OMSGallery-prefixed solutions for third-party identities in 2025. Traffic Analytics activates automatically when VNet flow logs point to a LAW workspace — no manual solution installation is required.

---

### action-groups.bicep

**File:** `modules/monitoring/action-groups.bicep`

#### Resources Created

| Resource | ARM Type | Name |
|---------|----------|------|
| Action Group | `Microsoft.Insights/actionGroups` | `ag-monitoring-dev` / `ag-monitoring-prod` |

#### Configuration and Rationale

```
location: 'global'
```
Action groups are always global — they are not tied to an Azure region. The location value is metadata only and does not affect notification functionality.

```
useCommonAlertSchema: true
```
Enabled on **all** receivers (email and webhook). Common Alert Schema normalises the content of alert notifications across all alert types (metric, log, activity log, health). Without this, each alert type has its own payload format, making it complex to build a single Power Automate flow or Logic App that handles all types. With this, the JSON schema is always the same.

**Webhook / Teams**

Teams integration is done via a Power Automate flow that receives the webhook and posts a formatted message to a Teams channel. The URL provided as `serviceUri` is the Power Automate HTTP trigger URL.

`useAadAuth: false` means standard HTTPS POST without Azure AD authentication. Set to `true` and configure Managed Identity if the endpoint requires an Azure AD token.

---

### alert-rules.bicep

**File:** `modules/monitoring/alert-rules.bicep`

#### Resources Created

5 KQL-based alert rules (`Microsoft.Insights/scheduledQueryRules@2022-06-15`):

| Resource Name | Display Name | Severity | Evaluation |
|-------------|-------------|-------------|------------|
| `alert-containerapps-errors-{env}` | Container Apps — Error spike | Warning (2) | Every 5 min, 10 min window |
| `alert-keyvault-throttling-{env}` | Key Vault — Throttling (HTTP 429) | Warning (2) | Every 5 min, 15 min window |
| `alert-frontdoor-5xx-{env}` | Front Door — 5xx error spike | Error (1) | Every 5 min, 10 min window |
| `alert-storage-errors-{env}` | Storage Account — Server errors | Warning (2) | Every 15 min, 30 min window |
| `alert-keyvault-secret-deleted-{env}` | Key Vault — Secret/Key deleted | Informational (3) | Every 15 min, 15 min window |

#### Severity Levels

| Value | Name | Typical Use |
|-------|------|-------------|
| 0 | Critical | Service down, immediate action required |
| 1 | Error | Clear failure affecting users |
| 2 | Warning | Declining trend, should be investigated |
| 3 | Informational | Event that should be recorded |
| 4 | Verbose | Debug information |

#### KQL Pattern Used

All rules use the same pattern:

```kql
-- Filter the table down to only rows representing a problem
-- Aggregate with bin() to count events per time window
-- WHERE on the count sets the threshold for what constitutes a problem
```

```
timeAggregation: 'Count'   -- counts the number of rows the query returns
threshold: 0               -- alert fires when row count > 0
operator: 'GreaterThan'
```

This means: the query returns rows **only** when there is a problem. The alert system counts these rows and fires when there are more than 0.

```
autoMitigate: true
```
Set to `true` on most rules: the alert closes automatically the next time the evaluation returns no rows. Set to `false` on Key Vault deletion since it is an irreversible event that should be manually acknowledged.

---

### eventhub-export.bicep

**File:** `modules/monitoring/eventhub-export.bicep`

#### Resources Created

| Resource | ARM Type |
|---------|----------|
| Event Hub Namespace | `Microsoft.EventHub/namespaces` |
| Event Hub | `Microsoft.EventHub/namespaces/eventhubs` |
| Authorization Rule "MonitorExport" | `Microsoft.EventHub/namespaces/authorizationRules` |
| Consumer Group "siem-consumer" | `Microsoft.EventHub/namespaces/eventhubs/consumergroups` |
| LAW Data Export Rule | `Microsoft.OperationalInsights/workspaces/dataExports` |

#### Configuration and Rationale

**Event Hub Namespace**

```
minimumTlsVersion: '1.2'
```
Rejects connections using TLS 1.0 or 1.1. Security best practice.

```
partitionCount: 4
```
4 partitions allow 4 parallel readers (SIEM consumers). Partition count cannot be changed after creation — plan ahead.

```
messageRetentionDays: 1
```
Kept short since the data is already in the LAW workspace. Event Hub is a streaming intermediary, not long-term storage.

**Authorization Rule**

Rights `Manage + Send + Listen` provide:
- **Send**: Azure Monitor / LAW uses this to write data
- **Listen**: The SIEM connector uses this to read
- **Manage**: Enables runtime administration (e.g. creating consumer groups)

**Consumer Group "siem-consumer"**

Azure Event Hub uses consumer groups to allow multiple independent readers to consume the same data stream without interfering with each other. A dedicated group for SIEM ensures the SIEM reader does not share position (offset) with other services that may also read from the Event Hub (e.g. Azure Stream Analytics).

**LAW Data Export Rule**

Configures continuous, automatic export of selected log tables from the workspace to the Event Hub namespace:

| Table | Contents |
|--------|---------|
| `AzureActivity` | All ARM operations (who created/deleted what) |
| `AzureDiagnostics` | Diagnostic logs from Key Vault, Front Door, etc. |
| `AzureMetrics` | Metric data from Azure resources |
| `StorageBlobLogs` | Blob operations (read, write, delete) |
| `ContainerAppConsoleLogs` | Application logs from Container Apps |
| `ContainerAppSystemLogs` | Platform events from Container Apps |

All tables are exported to **one** Event Hub (not one hub per table). This is controlled by `metaData.eventHubName` in the export rule.

**Important:** Tables that do not exist in the workspace (e.g. because no resource is sending `StorageBlobLogs` yet) are silently ignored. The export rule does not fail.

**Connection String in Outputs**

The Event Hub connection string is **not** exposed as a Bicep output. This is a deliberate choice: the Bicep linter rule `outputs-should-not-contain-secrets` flags `listKeys()` in outputs as a security risk because outputs are stored in the ARM deployment history (visible to anyone with read access to the resource group). Instead, `authorizationRuleId` is exposed — the connection string should be retrieved via Key Vault or via `az eventhubs namespace authorization-rule keys list` after deployment.

---

## Diagnostic Modules

### Bicep Scope Pattern

All diagnostic modules follow a specific pattern due to a Bicep constraint:

> A resource in a Bicep file cannot have `scope:` set to a different resource group than where the file itself is deployed.

**The solution:** The module is deployed in the correct resource group via the `scope:` property on the **module call** in `main.bicep`, not inside the module. This means each diag module can be deployed in the same resource group as the resource it configures.

```bicep
// In main.bicep:
module diagFrontDoor './modules/diag/diag-frontdoor.bicep' = if (!empty(frontDoorProfileName)) {
  name: 'deploy-diag-frontdoor'
  scope: resourceGroup(frontDoorResourceGroupName)  // ← Deployed in Front Door's RG
  params: { ... }
}
```

```bicep
// In diag-frontdoor.bicep:
resource frontDoor 'Microsoft.Cdn/profiles@2023-05-01' existing = {
  name: frontDoorProfileName
  // No explicit scope — the module IS already in the correct RG
}
```

All modules are **conditional**: `= if (!empty(resourceName))`. Resources with an empty name are skipped entirely — no partial deployment.

---

### diag-frontdoor.bicep

**File:** `modules/diag/diag-frontdoor.bicep`
**Deployed in:** Front Door's resource group

#### What is Configured

Diagnostic settings on the Front Door profile (`Microsoft.Insights/diagnosticSettings`):

| Category | Contents | Use |
|----------|---------|------|
| `FrontDoorAccessLog` | All HTTP requests: URL, method, status code, latency, POP, client IP | Performance analysis, troubleshooting, 4xx/5xx tracking |
| `FrontDoorHealthProbeLog` | Health check results per origin/backend | Identifying degraded backends |
| `FrontDoorWebApplicationFirewallLog` | WAF rule hits and blocks | Security monitoring, WAF rule tuning |
| `AllMetrics` | Aggregated metrics (e.g. RequestCount, OriginLatency) | Dashboards and metric alerts |

Event Hub streaming is optional: the `eventHubAuthorizationRuleId` and `eventHubName` parameters can be left empty to send only to LAW.

---

### diag-containerapps.bicep

**File:** `modules/diag/diag-containerapps.bicep`
**Deployed in:** Container Apps' resource group

#### What is Configured

Diagnostic settings on the **Managed Environment** (not on individual container apps):

| Category | LAW Table | Contents |
|----------|------------|---------|
| `ContainerAppConsoleLogs` | `ContainerAppConsoleLogs` | stdout/stderr from all container replicas |
| `ContainerAppSystemLogs` | `ContainerAppSystemLogs` | Platform events: startup, shutdown, crash, scaling |

**Why at Environment level, not on the individual app?**

The Container Apps architecture is such that logs flow through the Managed Environment layer. Setting diagnostics at the environment level captures logs from *all* apps running in that environment — now and in the future. Setting it on individual apps requires reconfiguration for every new app.

---

### diag-vnet.bicep

**File:** `modules/diag/diag-vnet.bicep`
**Deployed in:** `NetworkWatcherRG` (where the Network Watcher resource lives)

#### Resources Created

| Resource | ARM Type |
|---------|----------|
| VNet Flow Log | `Microsoft.Network/networkWatchers/flowLogs@2024-01-01` |

#### Configuration and Rationale

**VNet Flow Logs replace NSG Flow Logs**

NSG Flow Logs were retired by Microsoft on 30 June 2025 — new NSG flow log resources can no longer be created. VNet Flow Logs are the official replacement and operate at VNet level: one configuration captures traffic on all subnets, both current and future.

**Why NetworkWatcherRG?**

The VNet Flow Log resource is a child of Network Watcher (`/providers/Microsoft.Network/networkWatchers/{name}/flowLogs/{name}`). Azure automatically creates one Network Watcher per region, and it lives in `NetworkWatcherRG`. The Bicep module is therefore deployed in this resource group via `scope: resourceGroup(networkWatcherResourceGroupName)` in main.bicep.

The VNet being monitored can be in any resource group — it is referenced only via ARM resource ID as a string parameter (`vnetResourceId`), not via a Bicep symbol reference. This avoids Bicep's cross-scope constraint.

**Flow Log Version 2**

```
format.version: 2
```

Version 2 adds byte counting per flow direction (in and out) and is required for Traffic Analytics integration.

**Traffic Analytics**

```
flowAnalyticsConfiguration:
  enabled: true
  workspaceId: <GUID>         ← workspaceCustomerId (not the ARM resource ID!)
  workspaceRegion: norwayeast
  workspaceResourceId: <ARM ID>
  trafficAnalyticsInterval: 10
```

Traffic Analytics requires two different workspace identifiers:
- `workspaceId`: Workspace GUID (retrieved from the `workspaceCustomerId` output in log-analytics.bicep)
- `workspaceResourceId`: Full ARM resource ID

These are two different values and cannot be used interchangeably. `trafficAnalyticsInterval: 10` gives aggregation every 10 minutes — near real-time. Alternatively, 60 minutes for lower cost.

Traffic Analytics is activated automatically by ARM when flow logs point to a LAW workspace — no separate solution installation is required.

**Storage Account (Required)**

Flow Logs require a storage account for raw JSON storage, even when Traffic Analytics is enabled. Traffic Analytics processes these files and sends aggregated data to LAW. The storage account is not used for long-term storage — the `retentionDays` parameter controls this.

---

### diag-storage.bicep

**File:** `modules/diag/diag-storage.bicep`
**Deployed in:** Storage Account's resource group

#### What is Configured

Two sets of diagnostic settings (storage resources are hierarchical in ARM):

**1. Storage Account (account level)**

```
metrics: Transaction
```

Metrics only at account level — there are no useful log categories here. `Transaction` provides aggregated counter data for all requests.

**2. Blob Service (`/blobServices/default`)**

| Category | Contents |
|----------|---------|
| `StorageRead` | GET, HEAD, GET ACL — who read what, from which IP, with which authentication method |
| `StorageWrite` | PUT, POST, COPY, SET ACL — all write operations |
| `StorageDelete` | DELETE, Undelete — delete operations |

**Why the blob service in particular?**

Blob Storage is the most common storage medium for sensitive data in Azure. Full operation logging is critical for:
- Security auditing: Who had access to sensitive data?
- Data leak detection: Unusually large GET requests, access from unknown IPs
- Compliance: Many regulations (GDPR, NIS2) require logs of data access

Logging is enabled on the blob service, not on the storage account resource itself, because that is where ARM has exposed the useful log categories.

---

### diag-keyvault.bicep

**File:** `modules/diag/diag-keyvault.bicep`
**Deployed in:** Key Vault's resource group

#### What is Configured

| Category | Contents | Use |
|----------|---------|------|
| `AuditEvent` | All operations: read secret, write secret, delete, access denied | Security auditing, compliance |
| `AzurePolicyEvaluationDetails` | Policy evaluation results | Compliance posture |
| `AllMetrics` | ServiceApiHit, ServiceApiLatency, ServiceApiResult | Availability and performance |

**Why `AuditEvent` is Critical**

Key Vault is the central secrets store in Azure. `AuditEvent` logs:
- **Who** (Azure AD object ID) read which secret
- **From which IP** the request came
- **Authentication method** (managed identity, service principal, user)
- **What happened** — including access denials

Without this logging, it is impossible to detect that a secret has been exposed to an unauthorised party.

---

## Orchestrator — main.bicep

**File:** `main.bicep`

`main.bicep` is deployed to the monitoring resource group (`rg-monitoring-dev` / `rg-monitoring-prod`) and orchestrates all modules.

### Module Dependencies

Bicep resolves dependencies automatically via output references. The order ARM deploys in:

```
1. logAnalytics          ← No dependencies
1. actionGroups          ← No dependencies (parallel with logAnalytics)
                ↓
2. alertRules            ← Needs workspaceId and actionGroupId
2. eventHubExport        ← Needs workspaceName
2. subscriptionDiag      ← Needs workspaceId
                ↓
3. diagFrontDoor         ← Needs workspaceId and eventHubAuthorizationRuleId
3. diagContainerApps     ← Needs workspaceId and eventHubAuthorizationRuleId
3. diagVnet              ← Needs workspaceId and workspaceCustomerId
3. diagStorage           ← Needs workspaceId and eventHubAuthorizationRuleId
3. diagKeyVault          ← Needs workspaceId and eventHubAuthorizationRuleId
```

### Conditional Deployment

```bicep
module diagFrontDoor ... = if (!empty(frontDoorProfileName)) { ... }
```

All diag modules are conditional. An empty resource name in the parameter file = the module is skipped entirely. This allows you to deploy the monitoring infrastructure (LAW, alerts, Event Hub) without the monitored resources existing yet.

### Retention Cap for VNet Flow Logs

```bicep
retentionDays: min(retentionInDays, 365)
```

ARM limits VNet Flow Log retention to 365 days (storage account limit), while LAW retention can be set up to 730 days. `min()` ensures the prod parameter of 90 days is passed correctly, but will not exceed 365 even if someone sets a higher value.

### Cross-Resource Group Scope

Each diag module is deployed in its respective resource group:

```bicep
scope: resourceGroup(frontDoorResourceGroupName)      // Front Door's RG
scope: resourceGroup(containerAppsResourceGroupName)  // Container Apps' RG
scope: resourceGroup(networkWatcherResourceGroupName)  // NetworkWatcherRG
scope: resourceGroup(storageResourceGroupName)         // Storage's RG
scope: resourceGroup(keyVaultResourceGroupName)        // Key Vault's RG
```

This requires the deployment principal (service principal or user) to have the `Contributor` role in **all** these resource groups.

---

## Parameter Files

### dev.bicepparam

| Parameter | Value | Rationale |
|-----------|-------|-------------|
| `retentionInDays` | 30 | Minimum LAW retention, minimises cost |
| `dailyQuotaGb` | 5 | Cap against unintended cost increase |
| `eventHubSku` | Standard | Basic SIEM integration |
| `trafficAnalyticsInterval` | 10 | Near real-time, acceptable in dev |

### prod.bicepparam

| Parameter | Value | Rationale |
|-----------|-------|-------------|
| `retentionInDays` | 90 | 3 months of history for trend analysis |
| `dailyQuotaGb` | 10 | Double dev for production volume |
| `emailReceivers` | 2 (OpsTeam + OnCall) | Separate addresses for operations and on-call |
| `eventHubNamespaceName` | `evhns-mon-prod-f15e0b18` | Suffix `f15e0b18` is the first 8 chars of the subscription ID — ensures global uniqueness |
| `vnetResourceId` | full ARM ID | Retrieved with `az network vnet show -g rg-network-prod -n vnet-monitoring-prod --query id -o tsv` |
| `flowLogStorageAccountId` | full ARM ID | Retrieved with `az storage account show -g rg-monitoring-prod -n stflowprod0b18 --query id -o tsv` |
| `storageAccountName` | `stmonprod0b18` | Globally unique via the subscription suffix |
| `keyVaultName` | `kv-mon-prod-f15e0b18` | Soft-delete reserves the name for 90 days after deletion |

---

## Design Decisions

### Workspace-based Application Insights

Chosen over classic App Insights because:
- Data is stored in the LAW database — can be combined with other logs in KQL
- Same retention policy as the rest of the workspace
- Classic App Insights has been announced as deprecated by Microsoft

### Common Alert Schema

Enabled on all action group receivers. The alternative — different payload formats per alert type — means a Teams flow or Logic App must handle 5+ different JSON structures.

### Event Hub over Direct SIEM Integration

Event Hub acts as a buffer between Azure Monitor and the SIEM solution. Benefits:
- The SIEM connector's read speed is independent of Azure Monitor's write speed
- Dedicated consumer group ensures different consumers don't interfere with each other
- Works with Sentinel, Splunk, Elastic, QRadar and others via built-in connectors

### No Secrets in Bicep Outputs

The Event Hub connection string is **not** exposed as output. Deployment outputs are stored in the ARM deployment history and are visible to anyone with read access to the resource group. Sensitive values should be retrieved via `az eventhubs namespace authorization-rule keys list` after deployment and stored in Key Vault.

### Modular Conditional Deployment

Diag modules are activated by filling in resource names in the parameter file. The benefit: you can deploy the entire monitoring infrastructure (LAW, alerts, Event Hub) on day one, and activate monitoring of individual resources as they are created — without changing the Bicep code.

### Teams Notifications via Power Automate

The classic Office 365 Incoming Webhook connector in Teams does not render the Azure Monitor Common Alert Schema payload. The solution uses a Power Automate flow with an HTTP trigger that receives the webhook call, parses the Common Alert Schema, and posts a formatted message to the Teams channel. This also enables future enrichment of the notification (e.g. adding links, adaptive cards).

---

## Alert Rules — KQL Reference

### Alert 1: Container Apps — Error Spike

```kql
ContainerAppConsoleLogs
| where TimeGenerated > ago(10m)
| where Log has_any ("Error", "Exception", "FATAL", "Unhandled")
| summarize ErrorCount = count() by ContainerAppName, bin(TimeGenerated, 5m)
| where ErrorCount > 10
```

**Triggers:** More than 10 error lines per app per 5-minute window.
**Table:** `ContainerAppConsoleLogs` — requires Container Apps diagnostic settings to be configured.

### Alert 2: Key Vault — Throttling

```kql
AzureDiagnostics
| where TimeGenerated > ago(15m)
| where ResourceProvider == "MICROSOFT.KEYVAULT"
| where httpStatusCode_d == 429.0
| summarize ThrottleCount = count() by Resource, bin(TimeGenerated, 5m)
| where ThrottleCount > 5
```

**Triggers:** More than 5 HTTP 429 responses from Key Vault per 5 min.
**Cause:** 429 means rate limiting — the client is sending too many requests. The most common cause is applications reading secrets from Key Vault on every request instead of caching them.

### Alert 3: Front Door — 5xx Error Spike

```kql
AzureDiagnostics
| where TimeGenerated > ago(10m)
| where ResourceProvider == "MICROSOFT.CDN"
| where Category == "FrontDoorAccessLog"
| where httpStatusCode_d >= 500 and httpStatusCode_d < 600
| summarize ErrorCount = count() by bin(TimeGenerated, 5m)
| where ErrorCount > 20
```

**Triggers:** More than 20 server-side errors (5xx) per 5 min through Front Door.
**Severity 1 (Error)** because this indicates that backends are down or misconfigured.

> **Note:** AFD Standard/Premium uses `httpStatusCode_d` (double) in `AzureDiagnostics`, not `httpStatusCode_s`. Numeric comparison therefore requires a float literal (`>= 500`) — not string operators.

### Alert 4: Storage — Server Errors

```kql
StorageBlobLogs
| where TimeGenerated > ago(30m)
| where toint(StatusCode) >= 500
| summarize ErrorCount = count() by AccountName, bin(TimeGenerated, 15m)
| where ErrorCount > 10
```

**Triggers:** More than 10 server-side errors per storage account per 15 min.
**Table:** `StorageBlobLogs` — requires Storage diagnostic settings to be configured.

> **Note:** The `StatusCode` column in `StorageBlobLogs` is of type `string`, not `int`. `toint()` is required for numeric comparison — without it KQL returns a type error.

### Alert 5: Key Vault — Secret/Key Deleted

```kql
AzureDiagnostics
| where TimeGenerated > ago(15m)
| where ResourceProvider == "MICROSOFT.KEYVAULT"
| where OperationName has_any ("SecretDelete", "KeyDelete", "CertificateDelete")
| project TimeGenerated, Resource, OperationName, CallerIPAddress, ResultType, requestUri_s
```

**Triggers:** Any deletion of a secret, key, or certificate.
**`autoMitigate: false`** — requires manual acknowledgement. A deletion is an irreversible event (even with soft-delete) that should always be verified.

> **Note:** The `identity_claim_oid_g` column does not exist in the Key Vault `AzureDiagnostics` schema. `ResultType` and `requestUri_s` are the actual columns that exist and provide equivalent context.

---

## Deployment

Deployment is split into two phases. Phase 1 sets up the monitoring infrastructure. Phase 2 activates the diagnostic modules as the monitored resources are created.

### Required Permissions

The deployment principal needs `Contributor` on:
- `rg-monitoring-prod` / `rg-monitoring-dev`
- `rg-network-prod`, `rg-storage-prod`, `rg-kv-prod`
- `NetworkWatcherRG`

### Prerequisites

```powershell
# Verify Azure CLI and Bicep are installed
az --version
az bicep version

# Log in and set subscription
az login
az account set --subscription "f15e0b18-0cc7-469d-83d5-64cf82a20343"

# Register resource providers (only required once per subscription)
az provider register --namespace Microsoft.App --wait
az provider register --namespace Microsoft.OperationalInsights --wait
```

---

### Phase 1 — Monitoring Baseline

Creates LAW, App Insights, Action Group, Alert Rules, and Event Hub. No monitored resources need to exist yet.

**1. Create resource groups**

```powershell
az group create --name rg-monitoring-prod --location norwayeast
az group create --name rg-network-prod    --location norwayeast
az group create --name rg-storage-prod    --location norwayeast
az group create --name rg-kv-prod         --location norwayeast
```

**2. Validate and deploy**

```powershell
az deployment group validate `
  --resource-group rg-monitoring-prod `
  --template-file main.bicep `
  --parameters parameters/prod.bicepparam

az deployment group what-if `
  --resource-group rg-monitoring-prod `
  --template-file main.bicep `
  --parameters parameters/prod.bicepparam

az deployment group create `
  --resource-group rg-monitoring-prod `
  --template-file main.bicep `
  --parameters parameters/prod.bicepparam `
  --name "monitoring-prod-baseline"
```

---

### Phase 2a — VNet, Storage and Key Vault Diagnostics

Create the monitored resources, then redeploy.

**1. Create resources**

```powershell
# Storage for VNet flow logs (in rg-monitoring-prod)
az storage account create `
  --name stflowprod0b18 `
  --resource-group rg-monitoring-prod `
  --location norwayeast `
  --sku Standard_LRS `
  --kind StorageV2

# Monitored storage account (in rg-storage-prod)
az storage account create `
  --name stmonprod0b18 `
  --resource-group rg-storage-prod `
  --location norwayeast `
  --sku Standard_LRS `
  --kind StorageV2

# Key Vault (in rg-kv-prod)
az keyvault create `
  --name kv-mon-prod-f15e0b18 `
  --resource-group rg-kv-prod `
  --location norwayeast

# VNet (in rg-network-prod)
az network vnet create `
  --name vnet-monitoring-prod `
  --resource-group rg-network-prod `
  --location norwayeast `
  --address-prefixes 10.0.0.0/16
```

**2. Redeploy — ensure `vnetName`, `storageAccountName` and `keyVaultName` are filled in `prod.bicepparam`**

```powershell
az deployment group create `
  --resource-group rg-monitoring-prod `
  --template-file main.bicep `
  --parameters parameters/prod.bicepparam `
  --name "monitoring-prod-phase2a"
```

---

### Phase 2b — Container Apps Environment and Front Door Diagnostics

> **Important:** The Container Apps Environment MUST be created with VNet integration from the start. It is not possible to add a VNet to an existing environment — it must be deleted and recreated.

**1. Create subnet for Container Apps**

The subnet is delegated to `Microsoft.App/environments` and cannot be shared with other resources. `/23` satisfies both Consumption and Workload Profiles requirements.

```powershell
az network vnet subnet create `
  --name snet-cae-prod `
  --vnet-name vnet-monitoring-prod `
  --resource-group rg-network-prod `
  --address-prefixes 10.0.0.0/23 `
  --delegations Microsoft.App/environments
```

**2. Retrieve subnet ID and LAW key**

```powershell
$subnetId = az network vnet subnet show `
  --name snet-cae-prod `
  --vnet-name vnet-monitoring-prod `
  --resource-group rg-network-prod `
  --query id -o tsv

$workspaceId = az monitor log-analytics workspace show `
  --resource-group rg-monitoring-prod `
  --workspace-name law-monitoring-prod `
  --query customerId -o tsv

$workspaceKey = az monitor log-analytics workspace get-shared-keys `
  --resource-group rg-monitoring-prod `
  --workspace-name law-monitoring-prod `
  --query primarySharedKey -o tsv
```

> `--logs-workspace-id` requires the workspace GUID (`customerId`), not the ARM resource ID. Without `--logs-workspace-id` and `--logs-workspace-key`, Azure automatically creates a new, separate LAW workspace.

**3. Create Container Apps Environment**

```powershell
az containerapp env create `
  --name cae-monitoring-prod `
  --resource-group rg-monitoring-prod `
  --location norwayeast `
  --infrastructure-subnet-resource-id $subnetId `
  --logs-workspace-id $workspaceId `
  --logs-workspace-key $workspaceKey
```

**4. Create Front Door**

```powershell
az afd profile create `
  --profile-name afd-monitoring-prod `
  --resource-group rg-monitoring-prod `
  --sku Standard_AzureFrontDoor
```

Use `Premium_AzureFrontDoor` for WAF with custom rules or Private Link to origins.

**5. Redeploy — ensure `containerAppsEnvironmentName` and `frontDoorProfileName` are filled in `prod.bicepparam`**

```powershell
az deployment group create `
  --resource-group rg-monitoring-prod `
  --template-file main.bicep `
  --parameters parameters/prod.bicepparam `
  --name "monitoring-prod-phase2b"
```

---

### General Pattern for Activating a New Resource

Fill in the resource name in `prod.bicepparam` and redeploy — Bicep is idempotent and only touches what has changed:

```bicep
// Example: activate Key Vault diagnostics
param keyVaultName = 'kv-mon-prod-f15e0b18'
param keyVaultResourceGroupName = 'rg-kv-prod'
```

```powershell
az deployment group create `
  --resource-group rg-monitoring-prod `
  --template-file main.bicep `
  --parameters parameters/prod.bicepparam
```

---

### Retrieve Event Hub Connection String

The connection string is not exposed as a Bicep output (security reasons). Retrieve it after deployment as follows:

```powershell
$ruleId = az deployment group show `
  --resource-group rg-monitoring-prod `
  --name monitoring-prod-baseline `
  --query properties.outputs.eventHubAuthorizationRuleId.value -o tsv

az eventhubs namespace authorization-rule keys list `
  --ids $ruleId `
  --query primaryConnectionString -o tsv
```

---

## Next Steps

### Status as of 2026-05-14

| Task | Status |
|---------|--------|
| Prod Phase 1 — baseline (LAW, EH, alerts, action group) | ✅ Deployed |
| Prod Phase 2a — VNet, Storage, Key Vault diag | ✅ Deployed |
| Prod Phase 2b — Container Apps, Front Door diag | ✅ Deployed |
| Prod — Teams notifications via Power Automate | ✅ Verified |
| Prod — Subscription Activity Log → LAW | ✅ In Bicep |
| Dev baseline (LAW, EH, alerts, action group) | ✅ Deployed |
| Dev Phase 2 — VNet, Storage, Key Vault, CAE, AFD diag | ✅ Deployed |
| Dev — Teams notifications via Power Automate | ✅ Configured |
| Dev — Subscription Activity Log → LAW | ✅ In Bicep |
| Dev — end-to-end alert test | ⬜ Run when KV DNS propagated (~2 min) |

### Activating a New Resource (General Pattern)

Fill in the resource name in the parameter file and redeploy — Bicep is idempotent and only touches what has changed:

```bicep
// In dev.bicepparam — example for Key Vault:
param keyVaultName = 'kv-mon-dev-f15e0b18'
param keyVaultResourceGroupName = 'rg-kv-dev'
```

```powershell
az deployment group create `
  --resource-group rg-monitoring-dev `
  --template-file main.bicep `
  --parameters parameters/dev.bicepparam
```

### Further Extensions

- **Azure Monitor Workbooks** — Visual dashboards built on KQL queries against the workspace
- **Metric alerts** — `Microsoft.Insights/metricAlerts` for CPU/memory on Container Apps (requires resource ID)
- **Alerting on AzureActivity** — Alert on PolicyAssignment changes, role assignments, resource deletions
- **Private endpoint** — Switch to private ingestion/query endpoints for LAW if network isolation is required
