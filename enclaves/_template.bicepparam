// Template — copy to enclave-<name>.bicepparam and fill in.
// This file is the ONLY thing that changes per enclave.
using '../main.bicep'

param enclaveName = '<name>'                  // lowercase, <=12 chars
param location = 'southafricanorth'
param retentionDays = 90
param dailyCapGb = 0                          // set a cap during pilot; 0 = uncapped
param enclaveReaderGroupId = ''               // Entra group objectId in the ENCLAVE tenant; '' skips RBAC

// ---- SOC profile ----
param profile = 'it'                          // 'ot' for LEC-style utility enclaves
param defenderForIotSubscriptionId = ''       // required when profile = 'ot'
param enableMde = true
param notificationWebhookUrl = ''             // Teams/Slack/internal webhook; '' skips playbook
param deployForwarderVm = false               // true for dev/demo; prod uses physical box + Arc
param forwarderSshPublicKey = ''              // required when deployForwarderVm = true

// ---- SC-200 training coverage (see soc-ops/07-training-tier2.md section 7) ----
// Leave false for client enclaves. Only enclave-demo/enclave-dev set enableXdrTraining
// true today (2026-07-16 scoping decision) — confirm with Jay before enabling elsewhere.
param enableXdrTraining = false
param defenderForCloudPricingTier = 'Free'
param enableDefenderForIdentityConnector = false   // needs a real MDI sensor first
param enableDefenderForCloudAppsConnector = false  // needs Defender for Cloud Apps onboarded first

param tags = {
  managedBy: 'dovetail-cyber'
  workload: 'sentinel-enclave'
  environment: '<dev|demo|prod>'
}
