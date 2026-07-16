<#
.SYNOPSIS
  Post-deployment health check for a Sentinel enclave.
  Verifies: RG, workspace, Sentinel onboarding, DCE, DCRs, forwarder heartbeat.

.EXAMPLE
  ./scripts/validate-enclave.ps1 -Enclave dev -SubscriptionId <enclave-sub-id>
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Enclave,
    [Parameter(Mandatory)] [string]$SubscriptionId,
    [int]$HeartbeatWindowMinutes = 10
)

$ErrorActionPreference = 'Stop'
$rg  = "dc-$Enclave-sentinel-rg"
$law = "law-dc-$Enclave-prod"
$pass = 0; $fail = 0

function Check([string]$Name, [scriptblock]$Test) {
    try {
        $result = & $Test
        if ($result) { Write-Host "[PASS] $Name" -ForegroundColor Green; $script:pass++ }
        else         { Write-Host "[FAIL] $Name" -ForegroundColor Red;   $script:fail++ }
    } catch {
        Write-Host "[FAIL] $Name — $($_.Exception.Message)" -ForegroundColor Red; $script:fail++
    }
}

az account set --subscription $SubscriptionId

Check "Resource group $rg exists" {
    (az group exists --name $rg) -eq 'true'
}

Check "Workspace $law exists" {
    $null -ne (az monitor log-analytics workspace show --resource-group $rg --workspace-name $law --query id -o tsv 2>$null)
}

Check "Sentinel onboarded" {
    $state = az rest --method GET --uri "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$rg/providers/Microsoft.OperationalInsights/workspaces/$law/providers/Microsoft.SecurityInsights/onboardingStates/default?api-version=2024-03-01" 2>$null | ConvertFrom-Json
    $null -ne $state.name
}

Check "DCE dce-dc-$Enclave exists" {
    $null -ne (az monitor data-collection endpoint show --resource-group $rg --name "dce-dc-$Enclave" --query id -o tsv 2>$null)
}

foreach ($dcr in @('winsec', 'syslog', 'cef')) {
    Check "DCR dcr-dc-$Enclave-$dcr exists" {
        $null -ne (az monitor data-collection rule show --resource-group $rg --name "dcr-dc-$Enclave-$dcr" --query id -o tsv 2>$null)
    }
}

Check "Forwarder heartbeat within $HeartbeatWindowMinutes min" {
    $wsGuid = az monitor log-analytics workspace show --resource-group $rg --workspace-name $law --query customerId -o tsv
    $q = "Heartbeat | where TimeGenerated > ago(${HeartbeatWindowMinutes}m) | summarize count()"
    $r = az monitor log-analytics query --workspace $wsGuid --analytics-query $q -o json 2>$null | ConvertFrom-Json
    ($r.Count -gt 0) -and ([int]$r[0].count_ -gt 0)
}

Write-Host "`n== $Enclave validation: $pass passed, $fail failed ==" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($fail -gt 0) { exit 1 }
