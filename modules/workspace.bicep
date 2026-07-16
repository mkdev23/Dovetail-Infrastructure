// Log Analytics workspace + Microsoft Sentinel onboarding
targetScope = 'resourceGroup'

param enclaveName string
param location string
param retentionDays int
param dailyCapGb int
param tags object

var workspaceName = 'law-dc-${enclaveName}-prod'

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018' // move to CapacityReservation once daily volume is known
    }
    retentionInDays: retentionDays
    workspaceCapping: dailyCapGb > 0 ? {
      dailyQuotaGb: dailyCapGb
    } : null
    features: {
      // required so enclave users scoped to the RG can query, and nothing wider
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Onboard the workspace to Microsoft Sentinel
resource sentinel 'Microsoft.SecurityInsights/onboardingStates@2024-03-01' = {
  scope: law
  name: 'default'
  properties: {
    customerManagedKey: false
  }
}

// Sentinel health/audit diagnostics back into the same workspace
resource sentinelHealth 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: law
  name: 'sentinel-health-audit'
  properties: {
    workspaceId: law.id
    logs: [
      { category: 'Audit', enabled: true }
    ]
  }
  dependsOn: [ sentinel ]
}

output workspaceId string = law.id
output workspaceName string = law.name
