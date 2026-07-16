// ============================================================
// Dovetail Cyber — Sentinel Enclave Factory
// Subscription-scoped entrypoint. One deployment = one enclave.
//
// Usage:
//   az deployment sub create \
//     --location southafricanorth \
//     --template-file main.bicep \
//     --parameters enclaves/enclave-dev.bicepparam
// ============================================================

targetScope = 'subscription'

@description('Short lowercase enclave identifier, e.g. dev, demo, lec, otdi')
@maxLength(12)
param enclaveName string

@description('Azure region')
param location string = 'southafricanorth'

@description('Log Analytics interactive retention in days')
@minValue(30)
@maxValue(730)
param retentionDays int = 90

@description('Daily ingestion cap in GB. 0 = uncapped.')
param dailyCapGb int = 0

@description('Object ID of the Entra group granted Sentinel Reader on this enclave. Empty string skips RBAC.')
param enclaveReaderGroupId string = ''

// ---- SOC profile switches ----
@description('Enclave profile: "ot" adds Defender for IoT connector + incident rule (LEC-style); "it" skips it.')
@allowed([ 'it', 'ot' ])
param profile string = 'it'

@description('Subscription where Defender for IoT is enabled (OT profile). Empty = skip D4IoT connector.')
param defenderForIotSubscriptionId string = ''

@description('Enable the Microsoft Defender for Endpoint connector.')
param enableMde bool = true

@description('Training-only: enable Defender for Cloud (CSPM, Free tier) + the Entra ID Identity Protection connector. Zero incremental cost. Per the 2026-07-16 scoping decision this is demo/dev only — see soc-ops/07-training-tier2.md section 7.')
param enableXdrTraining bool = false

@description('Defender for Cloud pricing tier when enableXdrTraining is true. Free = Secure Score/recommendations, no cost. Standard = Defender CSPM (attack path analysis, agentless scanning), incurs real cost — confirm with Jay before setting this.')
@allowed([ 'Free', 'Standard' ])
param defenderForCloudPricingTier string = 'Free'

@description('Enable the Microsoft Defender for Identity connector. Requires an MDI sensor already installed at the client tenant — see modules/connectors.bicep for why this defaults false.')
param enableDefenderForIdentityConnector bool = false

@description('Enable the Microsoft Defender for Cloud Apps connector. Requires Defender for Cloud Apps already licensed/onboarded at the client tenant — see modules/connectors.bicep for why this defaults false.')
param enableDefenderForCloudAppsConnector bool = false

@description('Webhook for High/Medium incident notifications (Teams/Slack/internal endpoint). Empty = skip playbook.')
@secure()
param notificationWebhookUrl string = ''

@description('Deploy the dev/demo forwarder VM (cloud twin of the on-prem egress server). Prod uses a physical box via Azure Arc.')
param deployForwarderVm bool = false

@description('SSH public key for the forwarder VM (required if deployForwarderVm = true)')
param forwarderSshPublicKey string = ''

param tags object = {
  managedBy: 'dovetail-cyber'
  workload: 'sentinel-enclave'
}

var rgName = 'dc-${enclaveName}-sentinel-rg'

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
  tags: union(tags, { enclave: enclaveName, profile: profile })
}

module workspace 'modules/workspace.bicep' = {
  name: 'ws-${enclaveName}'
  scope: rg
  params: {
    enclaveName: enclaveName
    location: location
    retentionDays: retentionDays
    dailyCapGb: dailyCapGb
    tags: tags
  }
}

module ingestion 'modules/ingestion.bicep' = {
  name: 'ingest-${enclaveName}'
  scope: rg
  params: {
    enclaveName: enclaveName
    location: location
    workspaceResourceId: workspace.outputs.workspaceId
    tags: tags
  }
}

module connectors 'modules/connectors.bicep' = {
  name: 'conn-${enclaveName}'
  scope: rg
  params: {
    workspaceName: workspace.outputs.workspaceName
    defenderForIotSubscriptionId: profile == 'ot' ? defenderForIotSubscriptionId : ''
    enableMde: enableMde
    enableXdrTraining: enableXdrTraining
    enableDefenderForIdentityConnector: enableDefenderForIdentityConnector
    enableDefenderForCloudAppsConnector: enableDefenderForCloudAppsConnector
  }
}

// Defender for Cloud (CSPM) — subscription-level singleton per plan name, so
// this converges safely even when multiple enclaves share one subscription
// (see CLAUDE.md section 4, the three demo enclaves in one Dovetail-Demo sub).
// Free tier costs nothing; see defenderForCloudPricingTier's description
// before ever setting Standard.
resource defenderForCloud 'Microsoft.Security/pricings@2024-01-01' = if (enableXdrTraining) {
  name: 'CloudPosture'
  properties: {
    pricingTier: defenderForCloudPricingTier
  }
}

module automation 'modules/automation.bicep' = {
  name: 'auto-${enclaveName}'
  scope: rg
  params: {
    enclaveName: enclaveName
    location: location
    workspaceName: workspace.outputs.workspaceName
    notificationWebhookUrl: notificationWebhookUrl
  }
}

module forwarder 'modules/forwarder.bicep' = if (deployForwarderVm) {
  name: 'fwd-${enclaveName}'
  scope: rg
  params: {
    enclaveName: enclaveName
    location: location
    dcrWinSecId: ingestion.outputs.dcrWinSecId
    dcrSyslogId: ingestion.outputs.dcrSyslogId
    dcrCefId: ingestion.outputs.dcrCefId
    adminSshPublicKey: forwarderSshPublicKey
  }
}

module rbac 'modules/rbac.bicep' = if (!empty(enclaveReaderGroupId)) {
  name: 'rbac-${enclaveName}'
  scope: rg
  params: {
    principalId: enclaveReaderGroupId
  }
}

output resourceGroupName string = rg.name
output workspaceId string = workspace.outputs.workspaceId
output workspaceName string = workspace.outputs.workspaceName
output dceLogsIngestionEndpoint string = ingestion.outputs.dceLogsIngestionEndpoint
