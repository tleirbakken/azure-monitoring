#Requires -Version 7.0
<#
.SYNOPSIS
    End-to-end alerttest — utløser reelle betingelser og ber deg verifisere at
    varsler ankommer e-post og Teams innen forventet tid.
.PARAMETER Environment
    'prod' eller 'dev'
.PARAMETER SkipCleanup
    Behold testressurser i Azure etter kjøring (for feilsøking).
.EXAMPLE
    .\Test-AlertEndToEnd.ps1 -Environment prod
#>
param(
    [ValidateSet('prod', 'dev')]
    [string]$Environment = 'prod',
    [switch]$SkipCleanup
)

$kvName    = "kv-mon-$Environment-f15e0b18"
$kvRg      = "rg-kv-$Environment"
$monRg     = "rg-monitoring-$Environment"
$secretName = "alert-test-$(Get-Date -Format 'yyyyMMddHHmm')"

Write-Host ""
Write-Host "=== End-to-end Alerttest — $($Environment.ToUpper()) ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Denne testen utløser reelle Azure Monitor-alerts." -ForegroundColor Yellow
Write-Host "Sjekk e-post og Teams-kanal etter hvert steg." -ForegroundColor Yellow
Write-Host ""

# ── Test 1: Key Vault — Secret deleted (alert-keyvault-secret-deleted) ────────
Write-Host "--- Test 1: Key Vault Secret Deleted ---" -ForegroundColor Cyan
Write-Host "Oppretter testhemmelighet '$secretName' i $kvName..."

az keyvault secret set --vault-name $kvName --name $secretName --value "alert-test-value" -o none
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Kunne ikke opprette hemmelighet. Sjekk at du har Key Vault Secrets Officer-rollen." -ForegroundColor Red
    exit 1
}
Write-Host "✅ Hemmelighet opprettet"

Write-Host "Sletter hemmelighet — trigger for 'Secret deleted'-alert..."
az keyvault secret delete --vault-name $kvName --name $secretName -o none
Write-Host "✅ Hemmelighet slettet — $(Get-Date -Format 'HH:mm:ss')"
Write-Host ""
Write-Host "  Forventet: Alert utløses innen 15 minutter" -ForegroundColor Yellow
Write-Host "  Sjekk: E-post til OpsTeam og OnCall, melding i Teams-kanal" -ForegroundColor Yellow
Write-Host "  KQL-bekreftelse (kjør i Log Analytics):" -ForegroundColor Yellow
Write-Host @"
  AzureDiagnostics
  | where TimeGenerated > ago(30m)
  | where ResourceProvider == "MICROSOFT.KEYVAULT"
  | where OperationName has_any ("SecretDelete", "KeyDelete", "CertificateDelete")
  | project TimeGenerated, Resource, OperationName, CallerIPAddress, ResultType
"@ -ForegroundColor DarkGray

if (-not $SkipCleanup) {
    Write-Host ""
    Write-Host "Gjenoppretter hemmelighet fra soft-delete (cleanup)..."
    Start-Sleep -Seconds 5
    az keyvault secret recover --vault-name $kvName --name $secretName -o none
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Hemmelighet gjenopprettet"
    } else {
        Write-Host "⚠️  Kunne ikke gjenopprette automatisk. Kjør manuelt:" -ForegroundColor Yellow
        Write-Host "   az keyvault secret recover --vault-name $kvName --name $secretName"
    }
}

Write-Host ""

# ── Test 2: Key Vault — Throttling (vanskeligere å utløse automatisk) ─────────
Write-Host "--- Test 2: Key Vault Throttling (manuell) ---" -ForegroundColor Cyan
Write-Host "Denne alerten krever >5 HTTP 429-svar fra Key Vault per 5 min."
Write-Host "Vanskelig å utløse i et normalt miljø (Azure throttler ved svært høy rate)."
Write-Host "Verifiser i stedet at alerten er korrekt konfigurert:"
Write-Host ""
Write-Host "  az monitor scheduled-query show -g $monRg -n alert-keyvault-throttling-$Environment --query 'properties.enabled' -o tsv" -ForegroundColor DarkGray
Write-Host ""

# ── Test 3: Storage — Server errors (krever faktiske 5xx-feil) ───────────────
Write-Host "--- Test 3: Storage Server Errors (manuell) ---" -ForegroundColor Cyan
Write-Host "Alerten utløses ved >10 HTTP 5xx-svar fra blob-tjenesten per 15 min."
Write-Host "KQL for å se nåværende 5xx-rate i StorageBlobLogs:"
Write-Host @"
  StorageBlobLogs
  | where TimeGenerated > ago(1h)
  | summarize Total = count(), Errors = countif(toint(StatusCode) >= 500)
    by AccountName, bin(TimeGenerated, 15m)
"@ -ForegroundColor DarkGray
Write-Host ""

# ── Test 4: Container Apps — Error spike (krever app som logger feil) ─────────
Write-Host "--- Test 4: Container Apps Error Spike (manuell) ---" -ForegroundColor Cyan
Write-Host "Alerten utløses ved >10 Error/Exception-linjer per app per 5 min."
Write-Host "KQL for å se nåværende feilrate:"
Write-Host @"
  ContainerAppConsoleLogs
  | where TimeGenerated > ago(1h)
  | where Log has_any ("Error", "Exception", "FATAL", "Unhandled")
  | summarize ErrorCount = count() by ContainerAppName, bin(TimeGenerated, 5m)
  | order by TimeGenerated desc
"@ -ForegroundColor DarkGray
Write-Host ""

# ── Test 5: Front Door 5xx (krever faktisk trafikk) ──────────────────────────
Write-Host "--- Test 5: Front Door 5xx (manuell) ---" -ForegroundColor Cyan
Write-Host "Alerten utløses ved >20 5xx-svar per 5 min gjennom Front Door."
Write-Host "KQL for å se nåværende 5xx-rate:"
Write-Host @"
  AzureDiagnostics
  | where TimeGenerated > ago(1h)
  | where ResourceProvider == "MICROSOFT.CDN"
  | where Category == "FrontDoorAccessLog"
  | summarize Total = count(), Errors5xx = countif(httpStatusCode_d >= 500 and httpStatusCode_d < 600)
    by bin(TimeGenerated, 5m)
  | order by TimeGenerated desc
"@ -ForegroundColor DarkGray
Write-Host ""

# ── Verifiser alerts i portalen ───────────────────────────────────────────────
Write-Host "--- Verifiser i Azure Monitor ---" -ForegroundColor Cyan
Write-Host "Se alle aktive og utløste alerts:"
Write-Host "  https://portal.azure.com/#view/Microsoft_Azure_Monitoring/AzureMonitoringBrowseBlade/~/alertsV2" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Direkte lenke til action group for å teste varsling manuelt:"

$agId = az monitor action-group show -g $monRg -n "ag-monitoring-$Environment" --query id -o tsv 2>$null
Write-Host "  az monitor action-group test --ids $agId --alert-type servicehealth" -ForegroundColor DarkGray
Write-Host ""
Write-Host "=== Alerttest fullført ===" -ForegroundColor Cyan
