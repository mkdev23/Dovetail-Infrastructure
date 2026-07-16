// Template — copy to enclave-lec.bicepparam and fill in.
// This file is the ONLY thing that changes per enclave.
using '../main.bicep'

param enclaveName = 'lec'                  // lowercase, <=12 chars
param location = 'southafricanorth'
param retentionDays = 90
param dailyCapGb = 0                          // set a cap during pilot; 0 = uncapped
param enclaveReaderGroupId = ''               // Entra group objectId in the ENCLAVE tenant; '' skips RBAC

// ---- SOC profile ----
param profile = 'ot'
param defenderForIotSubscriptionId = ''       // required when profile = 'ot'
param enableMde = true
param notificationWebhookUrl = ''             // Teams/Slack/internal webhook; '' skips playbook
param deployForwarderVm = false               // true for dev/demo; prod uses physical box + Arc
param forwarderSshPublicKey = ''              // required when deployForwarderVm = true

// ---- SC-200 training coverage ----
// Deliberately OFF for this production client enclave — per the 2026-07-16 scoping
// decision, the full-suite training additions are demo/dev only until there's a real
// cost/rollout conversation with Jay about extending them to client enclaves.
param enableXdrTraining = false
param enableDefenderForIdentityConnector = false
param enableDefenderForCloudAppsConnector = false

param tags = {
  managedBy: 'dovetail-cyber'
  workload: 'sentinel-enclave'
  environment: 'prod'
}
