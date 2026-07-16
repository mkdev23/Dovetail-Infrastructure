<#
.SYNOPSIS
  Deploys (or re-deploys — idempotent) one Sentinel enclave.

.EXAMPLE
  # From the Dovetail SOC context, targeting the enclave's subscription:
  ./scripts/deploy-enclave.ps1 -Enclave dev -SubscriptionId <enclave-sub-id>

.NOTES
  Prereqs: az CLI logged in with rights on the target subscription
  (direct Owner during build phase, or Lighthouse-delegated Contributor after).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Enclave,
    [Parameter(Mandatory)] [string]$SubscriptionId,
    [string]$Location = 'southafricanorth',
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$repoRoot   = Split-Path -Parent $PSScriptRoot
$paramFile  = Join-Path $repoRoot "enclaves/enclave-$Enclave.bicepparam"
$template   = Join-Path $repoRoot 'main.bicep'

if (-not (Test-Path $paramFile)) {
    throw "No parameter file for enclave '$Enclave'. Copy enclaves/_template.bicepparam to enclaves/enclave-$Enclave.bicepparam first."
}

Write-Host "== Enclave factory: $Enclave ==" -ForegroundColor Cyan
az account set --subscription $SubscriptionId

$deploymentName = "enclave-$Enclave-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$azArgs = @(
    'deployment', 'sub', 'create',
    '--name', $deploymentName,
    '--location', $Location,
    '--template-file', $template,
    '--parameters', $paramFile
)
if ($WhatIf) { $azArgs += '--what-if' }

az @azArgs
if ($LASTEXITCODE -ne 0) { throw "Deployment failed for enclave '$Enclave'." }

if (-not $WhatIf) {
    Write-Host "`nDeployment complete. Outputs:" -ForegroundColor Green
    az deployment sub show --name $deploymentName --query 'properties.outputs' -o json
    Write-Host "`nNext steps:" -ForegroundColor Yellow
    Write-Host "  1. Connect workspace to Sentinel Repositories (content/ in this repo)"
    Write-Host "  2. Associate forwarder VMs to the DCRs (az monitor data-collection rule association create)"
    Write-Host "  3. Run ./scripts/validate-enclave.ps1 -Enclave $Enclave -SubscriptionId $SubscriptionId"
}
