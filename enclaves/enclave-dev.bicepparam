// Template — copy to enclave-dev.bicepparam and fill in.
// This file is the ONLY thing that changes per enclave.
using '../main.bicep'

param enclaveName = 'dev'                  // lowercase, <=12 chars
param location = 'southafricanorth'
param retentionDays = 90
param dailyCapGb = 2
param enclaveReaderGroupId = ''               // Entra group objectId in the ENCLAVE tenant; '' skips RBAC

// ---- SOC profile ----
param profile = 'ot'                          // SIMULATED OT — validates the customer OT pipeline, not Dovetail's own env
param defenderForIotSubscriptionId = ''       // required when profile = 'ot'
param enableMde = false                       // no endpoints in the lab tenant yet — enable once MDE is licensed
param notificationWebhookUrl = ''             // Teams/Slack/internal webhook; '' skips playbook
param deployForwarderVm = true                 // cloud twin of the egress server
param forwarderSshPublicKey = ''              // required when deployForwarderVm = true

param tags = {
  managedBy: 'dovetail-cyber'
  workload: 'sentinel-enclave'
  environment: 'lab'                    // simulated OT — Dovetail has no real OT; this exercises the customer pipeline
}
