[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('dev', 'prod')]
    [string]$Environment
)

$ErrorActionPreference = 'Stop'

$subscriptionId = switch ($Environment) {
    'dev'  { 'YOUR-DEV-SUBSCRIPTION-ID' }
    'prod' { 'YOUR-PROD-SUBSCRIPTION-ID' }
}

$resourceGroup = "rg-monitoring-$Environment"
$paramFile     = "$PSScriptRoot\..\parameters\$Environment.bicepparam"
$mainBicep     = "$PSScriptRoot\..\main.bicep"

Write-Host "Kobler til Azure..." -ForegroundColor Cyan
az account set --subscription $subscriptionId

Write-Host "Validerer Bicep-mal for $Environment..." -ForegroundColor Cyan
az deployment group validate `
    --resource-group $resourceGroup `
    --template-file $mainBicep `
    --parameters $paramFile `
    --output table

Write-Host "Kjører what-if..." -ForegroundColor Cyan
az deployment group what-if `
    --resource-group $resourceGroup `
    --template-file $mainBicep `
    --parameters $paramFile