# Deployment Guide — Azure Monitor Solution

This guide covers a complete clean deployment to a new Azure subscription.
Follow the steps in order. Every command is meant to be run from the **root of this repository**.

---

## Before You Start — Collect These Values

You need the following before running any commands. Gather them first.

| Value | Where to find it | Example |
|-------|-----------------|---------|
| **Subscription ID** | Azure Portal → Subscriptions | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| **OpsTeam email** | Your ops team email address | `ops@contoso.com` |
| **OnCall email** | A different on-call email address | `oncall@contoso.com` |
| **Teams webhook URL** | Created in Step 7 below | `https://...powerplatform.com/...` |

---

## Step 1 — Install Tools

```powershell
# Verify Azure CLI is installed (must be 2.50.0 or later)
az --version

# Install/upgrade Bicep
az bicep install
az bicep upgrade

# Verify PowerShell version (must be 7.0 or later)
$PSVersionTable.PSVersion
```

If Azure CLI is not installed: https://learn.microsoft.com/cli/azure/install-azure-cli

---

## Step 2 — Log In and Set Subscription

```powershell
az login

# List available subscriptions to find your subscription ID
az account list --query "[].{name:name, id:id}" -o table

# Set the subscription you want to deploy to
az account set --subscription "<YOUR-SUBSCRIPTION-ID>"

# Verify you are on the correct subscription
az account show --query "{name:name, id:id}" -o table
```

---

## Step 3 — Update Parameter Files

The parameter files contain values from the original subscription that **must be updated** before deployment.

### 3a — Update prod.bicepparam

Open [parameters/prod.bicepparam](parameters/prod.bicepparam) and change the following:

**Email addresses** (lines 17–21):
```bicep
param emailReceivers = [
  {
    name: 'OpsTeam'
    emailAddress: 'YOUR-OPS-EMAIL@contoso.com'        // ← change this
  }
  {
    name: 'OnCall'
    emailAddress: 'YOUR-ONCALL-EMAIL@contoso.com'     // ← change this
  }
]
```

**Event Hub namespace** — must be globally unique. Replace `f15e0b18` with the first 8 characters of your new subscription ID:
```bicep
param eventHubNamespaceName = 'evhns-mon-prod-XXXXXXXX'   // ← your 8-char suffix
```

**VNet resource ID** — replace the subscription ID in the path:
```bicep
param vnetResourceId = '/subscriptions/YOUR-SUBSCRIPTION-ID/resourceGroups/rg-network-prod/providers/Microsoft.Network/virtualNetworks/vnet-monitoring-prod'
```

**Flow log storage account ID** — replace the subscription ID:
```bicep
param flowLogStorageAccountId = '/subscriptions/YOUR-SUBSCRIPTION-ID/resourceGroups/rg-monitoring-prod/providers/Microsoft.Storage/storageAccounts/stflowprodXXXXXXXX'
```

**Storage account name** — must be globally unique (3–24 lowercase letters and numbers):
```bicep
param storageAccountName = 'stmonprodXXXXXXXX'    // ← your 8-char suffix
```

**Key Vault name** — must be globally unique (3–24 chars):
```bicep
param keyVaultName = 'kv-mon-prod-XXXXXXXX'       // ← your 8-char suffix
```

**Teams webhook** — leave as empty string for now, filled in Step 7:
```bicep
param webhookReceivers = [
  {
    name: 'TeamsOpsChannel'
    serviceUri: ''    // ← fill in after Step 7
  }
]
```

### 3b — Update dev.bicepparam

Open [parameters/dev.bicepparam](parameters/dev.bicepparam) and make the same changes for dev:

```bicep
// Email
param emailReceivers = [
  {
    name: 'OpsTeam'
    emailAddress: 'YOUR-OPS-EMAIL@contoso.com'
  }
]

// Event Hub namespace
param eventHubNamespaceName = 'evhns-mon-dev-XXXXXXXX'

// Leave all diag resource names empty for now — filled in Step 10
param frontDoorProfileName = ''
param containerAppsEnvironmentName = ''
param vnetName = ''
param vnetResourceId = ''
param flowLogStorageAccountId = ''
param storageAccountName = ''
param keyVaultName = ''

// Teams webhook — fill in after Step 7
param webhookReceivers = [
  {
    name: 'TeamsOpsChannel'
    serviceUri: ''
  }
]
```

---

## Step 4 — Register Resource Providers

Only required once per subscription.

```powershell
az provider register --namespace Microsoft.App --wait
az provider register --namespace Microsoft.OperationalInsights --wait
az provider register --namespace Microsoft.Insights --wait
az provider register --namespace Microsoft.EventHub --wait
az provider register --namespace Microsoft.KeyVault --wait
az provider register --namespace Microsoft.Network --wait

Write-Host "All providers registered"
```

---

## Step 5 — Create Resource Groups

```powershell
$location = "norwayeast"   # change if deploying to a different region

# Prod
az group create --name rg-monitoring-prod --location $location
az group create --name rg-network-prod    --location $location
az group create --name rg-storage-prod    --location $location
az group create --name rg-kv-prod         --location $location

# Dev
az group create --name rg-monitoring-dev --location $location
az group create --name rg-network-dev    --location $location
az group create --name rg-storage-dev    --location $location
az group create --name rg-kv-dev         --location $location

Write-Host "All resource groups created"
```

---

## Step 6 — Create Azure Resources

These resources must exist **before** the Bicep deployment activates the diagnostic modules.

Replace `XXXXXXXX` with the same 8-character suffix you chose in Step 3.

```powershell
$suffix = "XXXXXXXX"   # ← your 8-char subscription ID prefix

# ── Prod resources ────────────────────────────────────────────────

# Storage for VNet flow logs
az storage account create `
  --name "stflowprod$suffix" `
  --resource-group rg-monitoring-prod `
  --location norwayeast `
  --sku Standard_LRS `
  --kind StorageV2

# Monitored storage account
az storage account create `
  --name "stmonprod$suffix" `
  --resource-group rg-storage-prod `
  --location norwayeast `
  --sku Standard_LRS `
  --kind StorageV2

# Key Vault
az keyvault create `
  --name "kv-mon-prod-$suffix" `
  --resource-group rg-kv-prod `
  --location norwayeast

# VNet
az network vnet create `
  --name vnet-monitoring-prod `
  --resource-group rg-network-prod `
  --location norwayeast `
  --address-prefixes 10.0.0.0/16

# Front Door
az afd profile create `
  --profile-name afd-monitoring-prod `
  --resource-group rg-monitoring-prod `
  --sku Standard_AzureFrontDoor

# ── Dev resources ─────────────────────────────────────────────────

# Storage for VNet flow logs
az storage account create `
  --name "stflowdev$suffix" `
  --resource-group rg-monitoring-dev `
  --location norwayeast `
  --sku Standard_LRS `
  --kind StorageV2

# Monitored storage account
az storage account create `
  --name "stmondev$suffix" `
  --resource-group rg-storage-dev `
  --location norwayeast `
  --sku Standard_LRS `
  --kind StorageV2

# Key Vault
az keyvault create `
  --name "kv-mon-dev-$suffix" `
  --resource-group rg-kv-dev `
  --location norwayeast

# VNet
az network vnet create `
  --name vnet-monitoring-dev `
  --resource-group rg-network-dev `
  --location norwayeast `
  --address-prefixes 10.1.0.0/16

# Front Door
az afd profile create `
  --profile-name afd-monitoring-dev `
  --resource-group rg-monitoring-dev `
  --sku Standard_AzureFrontDoor

Write-Host "All resources created"
```

---

## Step 6b — Create Container Apps Environments

> **Critical:** The Container Apps Environment **must** be created with VNet integration from the start. Adding a VNet to an existing environment is not possible — it must be deleted and recreated.

### Prod

```powershell
# Create subnet (must be dedicated — cannot be shared with other resources)
az network vnet subnet create `
  --name snet-cae-prod `
  --vnet-name vnet-monitoring-prod `
  --resource-group rg-network-prod `
  --address-prefixes 10.0.0.0/23 `
  --delegations Microsoft.App/environments

# Retrieve IDs needed for the environment
$subnetId = az network vnet subnet show `
  --name snet-cae-prod `
  --vnet-name vnet-monitoring-prod `
  --resource-group rg-network-prod `
  --query id -o tsv

# Note: workspaceId here is the GUID (customerId), NOT the ARM resource ID
# The LAW workspace must exist first — deploy Phase 1 Bicep (Step 8) before this
$workspaceId = az monitor log-analytics workspace show `
  --resource-group rg-monitoring-prod `
  --workspace-name law-monitoring-prod `
  --query customerId -o tsv

$workspaceKey = az monitor log-analytics workspace get-shared-keys `
  --resource-group rg-monitoring-prod `
  --workspace-name law-monitoring-prod `
  --query primarySharedKey -o tsv

az containerapp env create `
  --name cae-monitoring-prod `
  --resource-group rg-monitoring-prod `
  --location norwayeast `
  --infrastructure-subnet-resource-id $subnetId `
  --logs-workspace-id $workspaceId `
  --logs-workspace-key $workspaceKey
```

### Dev

```powershell
az network vnet subnet create `
  --name snet-cae-dev `
  --vnet-name vnet-monitoring-dev `
  --resource-group rg-network-dev `
  --address-prefixes 10.1.0.0/23 `
  --delegations Microsoft.App/environments

$subnetId = az network vnet subnet show `
  --name snet-cae-dev `
  --vnet-name vnet-monitoring-dev `
  --resource-group rg-network-dev `
  --query id -o tsv

$workspaceId = az monitor log-analytics workspace show `
  --resource-group rg-monitoring-dev `
  --workspace-name law-monitoring-dev `
  --query customerId -o tsv

$workspaceKey = az monitor log-analytics workspace get-shared-keys `
  --resource-group rg-monitoring-dev `
  --workspace-name law-monitoring-dev `
  --query primarySharedKey -o tsv

az containerapp env create `
  --name cae-monitoring-dev `
  --resource-group rg-monitoring-dev `
  --location norwayeast `
  --infrastructure-subnet-resource-id $subnetId `
  --logs-workspace-id $workspaceId `
  --logs-workspace-key $workspaceKey
```

---

## Step 7 — Set Up Teams Notifications (Power Automate)

Azure Monitor's Common Alert Schema is not rendered by the classic Teams Incoming Webhook connector. Use Power Automate instead.

### Create the flow

1. Go to [make.powerautomate.com](https://make.powerautomate.com) and sign in
2. Click **+ New flow** → **Instant cloud flow** → **Skip**
3. Click **Add a trigger** → search for `request` → select **"When a HTTP request is received"** (under Built-in)
4. In the trigger, click **"Use sample payload to generate schema"** and paste:

```json
{
  "schemaId": "azureMonitorCommonAlertSchema",
  "data": {
    "essentials": {
      "alertRule": "alert-keyvault-secret-deleted-prod",
      "severity": "Sev3",
      "monitorCondition": "Fired",
      "description": "A secret or key was deleted in Key Vault",
      "firedDateTime": "2026-01-01T12:00:00Z"
    }
  }
}
```

5. Click **Done**
6. Click **+ New step** → search `post message` → select **Microsoft Teams** → **"Post message in a chat or channel"**
7. Sign in to Teams when prompted
8. Fill in:
   - **Post as**: `Flow bot`
   - **Post in**: `Channel`
   - **Team**: your team
   - **Channel**: your alerts channel
9. In **Message**, build the text using **Dynamic content** (lightning bolt icon):

```
🚨 [severity] — [alertRule]
Status: [monitorCondition]
[description]
Time: [firedDateTime]
```

10. In the trigger step, change **"Who can trigger the flow?"** to **`Anyone`**
11. Click **Save**
12. Expand the trigger step and copy the **HTTP URL**

### Update parameter files with the URL

In **both** `parameters/prod.bicepparam` and `parameters/dev.bicepparam`, replace the empty `serviceUri`:

```bicep
param webhookReceivers = [
  {
    name: 'TeamsOpsChannel'
    serviceUri: 'https://YOUR-POWER-AUTOMATE-URL-HERE'
  }
]
```

### Test the flow

```powershell
$url = "https://YOUR-POWER-AUTOMATE-URL-HERE"

$body = @{
    schemaId = "azureMonitorCommonAlertSchema"
    data = @{
        essentials = @{
            alertRule        = "test-alert"
            severity         = "Sev2"
            monitorCondition = "Fired"
            description      = "Test message from PowerShell"
            firedDateTime    = (Get-Date -Format "o")
        }
    }
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Method Post -Uri $url -Body $body -ContentType "application/json"
```

A message should appear in your Teams channel. If it does, proceed.

---

## Step 8 — Phase 1 Bicep Deployment (Prod)

This deploys the core monitoring infrastructure: LAW, App Insights, Action Group, Alert Rules, Event Hub, and Subscription Activity Log diagnostic setting.

```powershell
# Validate — check for errors before deploying
az deployment group validate `
  --resource-group rg-monitoring-prod `
  --template-file main.bicep `
  --parameters parameters/prod.bicepparam

# What-if — preview what will be created
az deployment group what-if `
  --resource-group rg-monitoring-prod `
  --template-file main.bicep `
  --parameters parameters/prod.bicepparam

# Deploy
az deployment group create `
  --resource-group rg-monitoring-prod `
  --template-file main.bicep `
  --parameters parameters/prod.bicepparam `
  --name "monitoring-prod-baseline"
```

Verify it succeeded:
```powershell
az deployment group show `
  --resource-group rg-monitoring-prod `
  --name monitoring-prod-baseline `
  --query "properties.provisioningState" -o tsv
# Expected output: Succeeded
```

> **After this step:** Run Step 6b (Container Apps Environment for prod) if you haven't already, since the LAW workspace now exists.

---

## Step 9 — Fill In Resource IDs in prod.bicepparam

Retrieve the ARM resource IDs that were created in Step 6 and add them to `prod.bicepparam`.

```powershell
$suffix = "XXXXXXXX"   # ← your suffix

# VNet resource ID
az network vnet show `
  --name vnet-monitoring-prod `
  --resource-group rg-network-prod `
  --query id -o tsv

# Flow log storage account ID
az storage account show `
  --name "stflowprod$suffix" `
  --resource-group rg-monitoring-prod `
  --query id -o tsv
```

Copy the output and update `prod.bicepparam`:

```bicep
param vnetName                = 'vnet-monitoring-prod'
param vnetResourceId          = '/subscriptions/YOUR-SUB-ID/resourceGroups/rg-network-prod/providers/Microsoft.Network/virtualNetworks/vnet-monitoring-prod'
param flowLogStorageAccountId = '/subscriptions/YOUR-SUB-ID/resourceGroups/rg-monitoring-prod/providers/Microsoft.Storage/storageAccounts/stflowprodXXXXXXXX'
param storageAccountName      = 'stmonprodXXXXXXXX'
param storageResourceGroupName = 'rg-storage-prod'
param keyVaultName            = 'kv-mon-prod-XXXXXXXX'
param keyVaultResourceGroupName = 'rg-kv-prod'
param frontDoorProfileName    = 'afd-monitoring-prod'
param frontDoorResourceGroupName = 'rg-monitoring-prod'
param containerAppsEnvironmentName = 'cae-monitoring-prod'
param containerAppsResourceGroupName = 'rg-monitoring-prod'
```

---

## Step 10 — Phase 2 Bicep Deployment (Prod)

Redeploy to activate all diagnostic modules now that the resources exist.

```powershell
az deployment group create `
  --resource-group rg-monitoring-prod `
  --template-file main.bicep `
  --parameters parameters/prod.bicepparam `
  --name "monitoring-prod-phase2"
```

---

## Step 11 — Phase 1 Bicep Deployment (Dev)

```powershell
az deployment group create `
  --resource-group rg-monitoring-dev `
  --template-file main.bicep `
  --parameters parameters/dev.bicepparam `
  --name "monitoring-dev-baseline"
```

> **After this step:** Run Step 6b (Container Apps Environment for dev) if you haven't already.

---

## Step 12 — Fill In Resource IDs in dev.bicepparam

```powershell
$suffix = "XXXXXXXX"

# VNet resource ID
az network vnet show `
  --name vnet-monitoring-dev `
  --resource-group rg-network-dev `
  --query id -o tsv

# Flow log storage account ID
az storage account show `
  --name "stflowdev$suffix" `
  --resource-group rg-monitoring-dev `
  --query id -o tsv
```

Update `dev.bicepparam` the same way as prod (Step 9), using the `dev` resource names.

---

## Step 13 — Phase 2 Bicep Deployment (Dev)

```powershell
az deployment group create `
  --resource-group rg-monitoring-dev `
  --template-file main.bicep `
  --parameters parameters/dev.bicepparam `
  --name "monitoring-dev-phase2"
```

---

## Step 14 — Grant Key Vault Access for Testing

To run the end-to-end alert test, your account needs the **Key Vault Secrets Officer** role on both Key Vaults.

```powershell
$myObjectId = az ad signed-in-user show --query id -o tsv

# Prod
$kvIdProd = az keyvault show --name "kv-mon-prod-XXXXXXXX" --resource-group rg-kv-prod --query id -o tsv
az role assignment create --assignee $myObjectId --role "Key Vault Secrets Officer" --scope $kvIdProd

# Dev
$kvIdDev = az keyvault show --name "kv-mon-dev-XXXXXXXX" --resource-group rg-kv-dev --query id -o tsv
az role assignment create --assignee $myObjectId --role "Key Vault Secrets Officer" --scope $kvIdDev
```

---

## Step 15 — Verify Configuration

Run the configuration test against both environments. This checks that all resources, alert rules, and diagnostic settings are correctly deployed.

```powershell
# Prod — expect 23+ PASS, 0 FAIL
.\tests\Test-MonitoringConfig.ps1 -Environment prod

# Dev — expect 20+ PASS, 0 FAIL
.\tests\Test-MonitoringConfig.ps1 -Environment dev
```

WARN on data flow checks (AzureActivity, StorageBlobLogs) is expected for a fresh deployment — data will appear within minutes.

---

## Step 16 — End-to-End Alert Test

This creates and deletes a test secret in Key Vault, triggering the `alert-keyvault-secret-deleted` alert. The alert fires within 15 minutes.

```powershell
# Wait ~2 minutes after creating the Key Vault before running this
# (DNS propagation for new Key Vaults)

.\tests\Test-AlertEndToEnd.ps1 -Environment prod
```

Within 15 minutes you should receive:
- ✅ An email to OpsTeam
- ✅ An email to OnCall
- ✅ A message in the Teams channel

---

## Deployment Order Summary

```
Step 1   Install tools
Step 2   Log in to Azure
Step 3   Update parameter files (subscription ID, emails, resource names)
Step 4   Register resource providers
Step 5   Create resource groups
Step 6   Create Azure resources (storage, Key Vault, VNet, Front Door)
Step 7   Set up Power Automate flow → update parameter files with webhook URL
Step 8   Deploy prod Phase 1 (Bicep baseline)
Step 6b  Create Container Apps Environment prod (needs LAW from Step 8)
Step 9   Fill in resource IDs in prod.bicepparam
Step 10  Deploy prod Phase 2 (Bicep — activates all diag modules)
Step 11  Deploy dev Phase 1 (Bicep baseline)
Step 6b  Create Container Apps Environment dev (needs LAW from Step 11)
Step 12  Fill in resource IDs in dev.bicepparam
Step 13  Deploy dev Phase 2 (Bicep — activates all diag modules)
Step 14  Grant Key Vault Secrets Officer role
Step 15  Run configuration tests
Step 16  Run end-to-end alert test
```

---

## Teardown — Delete Everything

Run in this order. Steps 1 and 2 remove resources that live **outside** resource groups and would be left behind if you only deleted the RGs.

### 1. Delete subscription-level diagnostic settings

```powershell
az monitor diagnostic-settings subscription delete --name "activity-to-law-prod" --yes
az monitor diagnostic-settings subscription delete --name "activity-to-law-dev" --yes
```

### 2. Delete VNet flow logs from NetworkWatcherRG

These are child resources of the Network Watcher and are not deleted when the RG is removed.
Note: `--location` is used instead of `-g` — the location identifies the correct Network Watcher automatically.

```powershell
az network watcher flow-log delete --location norwayeast -n "flowlog-vnet-monitoring-prod-prod"
az network watcher flow-log delete --location norwayeast -n "flowlog-vnet-monitoring-dev-dev"
```

### 3. Delete all resource groups

`--no-wait` runs all deletions in parallel. Each RG takes 2–5 minutes.

```powershell
az group delete --name rg-monitoring-prod --yes --no-wait
az group delete --name rg-monitoring-dev  --yes --no-wait
az group delete --name rg-network-prod    --yes --no-wait
az group delete --name rg-network-dev     --yes --no-wait
az group delete --name rg-storage-prod    --yes --no-wait
az group delete --name rg-storage-dev     --yes --no-wait
az group delete --name rg-kv-prod         --yes --no-wait
az group delete --name rg-kv-dev          --yes --no-wait
```

### 4. Purge soft-deleted Key Vaults

Key Vault soft-delete reserves the name for 90 days after deletion. Run this after the RG deletions complete (verify with `az group show --name rg-kv-prod` returning an error before purging).

Replace `XXXXXXXX` with your suffix.

```powershell
az keyvault purge --name "kv-mon-prod-XXXXXXXX" --location norwayeast
az keyvault purge --name "kv-mon-dev-XXXXXXXX"  --location norwayeast
```

> Skip this step if you are redeploying to a **different subscription** — the names won't conflict since you'll use a new suffix.

### 5. Delete the Power Automate flow (optional)

Go to [make.powerautomate.com](https://make.powerautomate.com) → **My flows** → select the flow → **Delete**.

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `NamespaceUnavailable` on Event Hub | Namespace name taken globally | Change suffix in `eventHubNamespaceName` |
| `ManagedEnvironmentCannotAddVnetToExistingEnv` | CAE created without VNet first | Delete the CAE and recreate with `--infrastructure-subnet-resource-id` |
| `DirectApiAuthorizationRequired` on Teams webhook | Wrong URL type copied from Power Automate | In the trigger, set **"Who can trigger the flow?"** to **Anyone** and recopy the URL |
| `ResourceNotFound` on diag modules | Target resource doesn't exist yet | Create the resource first, then redeploy |
| `NsgFlowLogCreationBlocked` | NSG flow logs retired June 2025 | Use `diag-vnet.bicep` which uses VNet flow logs instead |
| KQL alert `invalid column` errors | Wrong column type in AzureDiagnostics | See KQL Reference in README.md — use `_d` suffix for numeric columns |
| Key Vault DNS resolution fails | New Key Vault DNS not propagated | Wait 2 minutes and retry |
