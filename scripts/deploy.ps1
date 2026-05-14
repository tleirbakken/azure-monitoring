[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('dev', 'prod')]
    [string]$Environment,

    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

$subscriptionId = switch ($Environment) {
    'dev'  { 'YOUR-DEV-SUBSCRIPTION-ID' }
    'prod' { 'YOUR-PROD-SUBSCRIPTION-ID' }
}

$resourceGroup     = "rg-monitoring-$Environment"
$deploymentName    = "deploy-monitoring-$(Get-Date -Format 'yyyyMMdd-HHmm')"
$paramFile         = "$PSScriptRoot\..\parameters\$Environment.bicepparam"
$mainBicep         = "$PSScriptRoot\..\main.bicep"

Write-Host "Kobler til subscription: $subscriptionId" -ForegroundColor Cyan
az account set --subscription $subscriptionId

# Opprett resource group hvis den ikke finnes
$rgExists = az group show --name $resourceGroup --query "name" -o tsv 2>$null
if (-not $rgExists) {
    Write-Host "Oppretter resource group: $resourceGroup" -ForegroundColor Yellow
    az group create --name $resourceGroup --location norwayeast
}

if ($WhatIf) {
    Write-Host "Kjører what-if for $Environment..." -ForegroundColor Yellow
    az deployment group what-if `
        --resource-group $resourceGroup `
        --name $deploymentName `
        --template-file $mainBicep `
        --parameters $paramFile
} else {
    Write-Host "Deployer til $Environment..." -ForegroundColor Green
    az deployment group create `
        --resource-group $resourceGroup `
        --name $deploymentName `
        --template-file $mainBicep `
        --parameters $paramFile `
        --output table

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Deploy fullført: $deploymentName" -ForegroundColor Green

        # Hent outputs
        az deployment group show `
            --resource-group $resourceGroup `
            --name $deploymentName `
            --query properties.outputs `
            --output json | Tee-Object -FilePath "$PSScriptRoot\..\deploy-output.json"
    } else {
        Write-Error "Deploy feilet. Sjekk Azure Portal Activity Log."
    }
}