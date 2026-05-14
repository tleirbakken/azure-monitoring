#Requires -Version 7.0
<#
.SYNOPSIS
    Verifiserer at alle monitoring-komponenter er korrekt konfigurert i Azure.
.PARAMETER Environment
    'prod' eller 'dev'
.EXAMPLE
    .\Test-MonitoringConfig.ps1 -Environment prod
#>
param(
    [ValidateSet('prod', 'dev')]
    [string]$Environment = 'prod'
)

$sub         = 'f15e0b18-0cc7-469d-83d5-64cf82a20343'
$monRg       = "rg-monitoring-$Environment"
$kvRg        = "rg-kv-$Environment"
$storageRg   = "rg-storage-$Environment"
$ehNs        = "evhns-mon-$Environment-f15e0b18"
$kvName      = "kv-mon-$Environment-f15e0b18"
$storageName = "stmon${Environment}0b18"

$script:passed   = 0
$script:failed   = 0
$script:warnings = 0
$script:results  = [System.Collections.Generic.List[PSCustomObject]]::new()

function Assert {
    param([string]$Label, [scriptblock]$Command, [switch]$Warn)
    $ok = $false
    try {
        $output = & $Command 2>&1
        $ok = ($LASTEXITCODE -eq 0) -and ($null -ne $output) -and ("$output".Trim() -ne '') -and ("$output" -notmatch '^ERROR')
    } catch { }

    if ($ok) {
        $script:passed++
        $script:results.Add([PSCustomObject]@{ Icon = 'PASS'; Test = $Label })
        Write-Host "  PASS  $Label"
    } elseif ($Warn) {
        $script:warnings++
        $script:results.Add([PSCustomObject]@{ Icon = 'WARN'; Test = $Label })
        Write-Host "  WARN  $Label  (ingen data enda — forventet for ny ressurs)"
    } else {
        $script:failed++
        $script:results.Add([PSCustomObject]@{ Icon = 'FAIL'; Test = $Label })
        Write-Host "  FAIL  $Label"
    }
}

Write-Host ""
Write-Host "=== Monitoring Config Test --- $($Environment.ToUpper()) ==="
Write-Host ""

# ── Kjerne-ressurser ──────────────────────────────────────────────────────────
Write-Host "[ Kjerne-ressurser ]"

Assert "LAW law-monitoring-$Environment" {
    az monitor log-analytics workspace show -g $monRg -n "law-monitoring-$Environment" --query name -o tsv 2>&1
}
Assert "App Insights appi-monitoring-$Environment" {
    az monitor app-insights component show -g $monRg -a "appi-monitoring-$Environment" --query name -o tsv 2>&1
}
Assert "Action Group ag-monitoring-$Environment" {
    az monitor action-group show -g $monRg -n "ag-monitoring-$Environment" --query name -o tsv 2>&1
}
Assert "Action Group — e-postmottaker OpsTeam" {
    $r = az monitor action-group show -g $monRg -n "ag-monitoring-$Environment" --query "emailReceivers[].name" -o tsv 2>&1
    if ("$r" -match 'OpsTeam') { "ok" } else { $global:LASTEXITCODE = 1 }
}
Assert "Action Group — webhook TeamsOpsChannel" {
    $r = az monitor action-group show -g $monRg -n "ag-monitoring-$Environment" --query "webhookReceivers[].name" -o tsv 2>&1
    if ("$r" -match 'TeamsOpsChannel') { "ok" } else { $global:LASTEXITCODE = 1 }
}
Assert "Event Hub Namespace $ehNs" {
    az eventhubs namespace show -g $monRg -n $ehNs --query name -o tsv 2>&1
}
Assert "Event Hub evh-monitoring-$Environment" {
    az eventhubs eventhub show -g $monRg --namespace-name $ehNs -n "evh-monitoring-$Environment" --query name -o tsv 2>&1
}
Assert "Event Hub consumer group siem-consumer" {
    az eventhubs eventhub consumer-group show -g $monRg --namespace-name $ehNs `
      --eventhub-name "evh-monitoring-$Environment" -n siem-consumer --query name -o tsv 2>&1
}
Assert "LAW data export til Event Hub" {
    az monitor log-analytics workspace data-export show -g $monRg `
      --workspace-name "law-monitoring-$Environment" -n "export-to-eventhub-$Environment" --query name -o tsv 2>&1
}
Assert "Subscription Activity Log -> LAW (activity-to-law-$Environment)" {
    az monitor diagnostic-settings subscription show -n "activity-to-law-$Environment" --query name -o tsv 2>&1
}

# ── Alert-regler ──────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[ Alert-regler ]"

# Merk: az monitor scheduled-query show pakker ut 'properties' — bruk --query "enabled", ikke "properties.enabled"
foreach ($rule in @(
    "alert-containerapps-errors-$Environment",
    "alert-keyvault-throttling-$Environment",
    "alert-frontdoor-5xx-$Environment",
    "alert-storage-errors-$Environment",
    "alert-keyvault-secret-deleted-$Environment"
)) {
    $ruleName = $rule
    Assert $ruleName {
        az monitor scheduled-query show -g $monRg -n $ruleName --query "enabled" -o tsv 2>&1
    }
}

# ── Diagnostikk-innstillinger ─────────────────────────────────────────────────
Write-Host ""
Write-Host "[ Diagnostikk-innstillinger ]"

Assert "Key Vault diag-to-law" {
    az monitor diagnostic-settings show `
      --resource "/subscriptions/$sub/resourceGroups/$kvRg/providers/Microsoft.KeyVault/vaults/$kvName" `
      -n diag-to-law --query name -o tsv 2>&1
}
Assert "Storage Account diag-to-law" {
    az monitor diagnostic-settings show `
      --resource "/subscriptions/$sub/resourceGroups/$storageRg/providers/Microsoft.Storage/storageAccounts/$storageName" `
      -n diag-to-law --query name -o tsv 2>&1
}
Assert "Storage Blob Service diag-to-law" {
    az monitor diagnostic-settings show `
      --resource "/subscriptions/$sub/resourceGroups/$storageRg/providers/Microsoft.Storage/storageAccounts/$storageName/blobServices/default" `
      -n diag-to-law --query name -o tsv 2>&1
}

# Merk: az network watcher flow-log show pakker ut 'properties' — bruk --query "enabled"
Assert "VNet Flow Log aktivert" {
    az network watcher flow-log show -g NetworkWatcherRG --location norwayeast `
      -n "flowlog-vnet-monitoring-$Environment-$Environment" --query "enabled" -o tsv 2>&1
}

if ($Environment -eq 'prod') {
    Assert "Container Apps Env diag-to-law" {
        az monitor diagnostic-settings show `
          --resource "/subscriptions/$sub/resourceGroups/$monRg/providers/Microsoft.App/managedEnvironments/cae-monitoring-prod" `
          -n diag-to-law --query name -o tsv 2>&1
    }
    Assert "Front Door diag-to-law" {
        az monitor diagnostic-settings show `
          --resource "/subscriptions/$sub/resourceGroups/$monRg/providers/Microsoft.Cdn/profiles/afd-monitoring-prod" `
          -n diag-to-law --query name -o tsv 2>&1
    }
}

# ── Dataflyt i LAW (KQL) ──────────────────────────────────────────────────────
# Sjekker om data faktisk ankommer. WARN (ikke FAIL) hvis 0 — kan være tomt for nye ressurser.
Write-Host ""
Write-Host "[ Dataflyt i LAW (siste 24 timer) ]"

$workspaceId = az monitor log-analytics workspace show -g $monRg -n "law-monitoring-$Environment" --query customerId -o tsv 2>$null

foreach ($t in @(
    @{ Label = "AzureActivity mottar data";        Query = "AzureActivity | where TimeGenerated > ago(24h) | count" },
    @{ Label = "AzureDiagnostics mottar data";     Query = "AzureDiagnostics | where TimeGenerated > ago(24h) | count" },
    @{ Label = "StorageBlobLogs mottar data";      Query = "StorageBlobLogs | where TimeGenerated > ago(24h) | count" },
    @{ Label = "KV AuditEvent mottar data";        Query = "AzureDiagnostics | where TimeGenerated > ago(24h) | where ResourceProvider == 'MICROSOFT.KEYVAULT' | where Category == 'AuditEvent' | count" }
)) {
    $label = $t.Label
    $query = $t.Query
    Assert $label -Warn {
        $count = az monitor log-analytics query -w $workspaceId --analytics-query $query --query "[0].Count" -o tsv 2>$null
        if ([int]$count -gt 0) { "ok" } else { $global:LASTEXITCODE = 1 }
    }
}

# ── Sammendrag ────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Sammendrag ==="
if ($script:failed -eq 0) {
    Write-Host "$($script:passed) bestatt, $($script:warnings) advarsler (ingen feil)"
} else {
    Write-Host "$($script:passed) bestatt, $($script:warnings) advarsler, $($script:failed) feilet"
    Write-Host ""
    Write-Host "Feilede sjekker:"
    $script:results | Where-Object { $_.Icon -eq 'FAIL' } | ForEach-Object { Write-Host "  - $($_.Test)" }
    exit 1
}
