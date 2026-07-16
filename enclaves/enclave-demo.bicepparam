// Template — copy to enclave-demo.bicepparam and fill in.
// This file is the ONLY thing that changes per enclave.
using '../main.bicep'

param enclaveName = 'demo'                  // lowercase, <=12 chars
param location = 'southafricanorth'
param retentionDays = 90
param dailyCapGb = 5
param enclaveReaderGroupId = ''               // Entra group objectId in the ENCLAVE tenant; '' skips RBAC

// ---- SOC profile ----
param profile = 'ot'
param defenderForIotSubscriptionId = ''       // required when profile = 'ot'
param enableMde = false                       // no endpoints in the lab tenant yet — enable once MDE is licensed
param notificationWebhookUrl = ''             // Teams/Slack/internal webhook; '' skips playbook
param deployForwarderVm = true
param forwarderSshPublicKey = ''              // required when deployForwarderVm = true

param tags = {
  managedBy: 'dovetail-cyber'
  workload: 'sentinel-enclave'
  environment: 'demo'                   // simulated OT for client demos — not a real Dovetail OT environment
}
