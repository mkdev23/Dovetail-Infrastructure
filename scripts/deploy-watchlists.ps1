<#
.SYNOPSIS
  Deploys/updates Sentinel watchlists from content/watchlists/*.csv.
  Watchlists aren't handled by Sentinel Repositories, so this script is the
  delivery path — run it per enclave after deploy, and re-run whenever the
  CSVs change. Idempotent: existing watchlists are replaced.

  NOTE: critical-assets.csv doubles as the EO 163 digital-asset inventory
  seed for the enclave. Keep it current — analytics rules join against it.

.EXAMPLE
  ./scripts/deploy-watchlists.ps1 -Enclave dev -SubscriptionId <enclave-sub-id>
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Enclave,
    [Parameter(Mandatory)] [string]$SubscriptionId
)

$ErrorActionPreference = 'Stop'
$rg  = "dc-$Enclave-sentinel-rg"
$law = "law-dc-$Enclave-prod"
$repoRoot = Split-Path -Parent $PSScriptRoot
$watchlistDir = Join-Path $repoRoot 'content/watchlists'

az account set --subscription $SubscriptionId

# Search key per watchlist = the column analytics rules join on
$searchKeys = @{
    'critical-assets' = 'hostname'
    'approved-admins' = 'account'
}

Get-ChildItem $watchlistDir -Filter *.csv | ForEach-Object {
    $alias = $_.BaseName
    $key   = $searchKeys[$alias]
    if (-not $key) { $key = ((Get-Content $_.FullName -First 1) -split ',')[0] }

    Write-Host "Deploying watchlist '$alias' (search key: $key)..." -ForegroundColor Cyan
    $csvContent = Get-Content $_.FullName -Raw

    $body = @{
        properties = @{
            displayName        = $alias
            provider           = 'Dovetail Cyber'
            source             = "$alias.csv"
            itemsSearchKey     = $key
            contentType        = 'text/csv'
            numberOfLinesToSkip = 0
            rawContent         = $csvContent
        }
    } | ConvertTo-Json -Depth 5

    $tmp = New-TemporaryFile
    $body | Set-Content $tmp -Encoding utf8

    az rest --method PUT `
        --uri "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$rg/providers/Microsoft.OperationalInsights/workspaces/$law/providers/Microsoft.SecurityInsights/watchlists/$alias`?api-version=2024-03-01" `
        --body "@$tmp" | Out-Null

    Remove-Item $tmp
    Write-Host "  -> deployed" -ForegroundColor Green
}

Write-Host "`nWatchlists deployed. Verify: Sentinel -> Watchlist blade in workspace $law" -ForegroundColor Yellow
