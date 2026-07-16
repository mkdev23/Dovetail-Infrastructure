// Sentinel data connectors for the LEC-style OT profile, plus the
// Microsoft-security incident-creation rules that promote their alerts
// to Sentinel incidents in the enclave workspace.
//
// enableXdrTraining / enableDefenderForIdentityConnector /
// enableDefenderForCloudAppsConnector add the rest of the SC-200-relevant
// Microsoft Defender suite, gated OFF by default — see the comment on each
// resource below for what's a real zero-extra-cost connector vs. what needs
// a product Jay hasn't provisioned yet (on-prem sensor, CASB config). Per
// the 2026-07-16 scoping decision, only enclave-demo/enclave-dev set these
// true today — see soc-ops/07-training-tier2.md §7.
targetScope = 'resourceGroup'

param workspaceName string

@description('Subscription ID where Defender for IoT is enabled for this enclave (usually the enclave subscription itself). Empty = skip D4IoT connector.')
param defenderForIotSubscriptionId string = ''

@description('Enable the Microsoft Defender for Endpoint connector (IT-side servers/workstations)')
param enableMde bool = true

@description('Training-only: enable the Entra ID Identity Protection connector (kind AzureActiveDirectory). Works on any Entra tier — risk-detection depth varies with P1/P2 licensing, but the connector itself needs nothing extra to deploy or produce some real alerts.')
param enableXdrTraining bool = false

@description('Enable the Microsoft Defender for Identity connector. NOT functional until an MDI sensor is installed next to the client tenant Domain Controllers — deploying this resource alone will not produce alerts. Leave false until that prerequisite is confirmed (see soc-ops/07-training-tier2.md section 7 — also flags a real open question for OT/diode enclaves like lec).')
param enableDefenderForIdentityConnector bool = false

@description('Enable the Microsoft Defender for Cloud Apps (MCAS) connector. NOT functional until Defender for Cloud Apps is licensed and onboarded (Conditional Access App Control / OAuth app connectors configured) at the client tenant — deploying this resource alone will not produce alerts. Leave false until that prerequisite is confirmed.')
param enableDefenderForCloudAppsConnector bool = false

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

// ---- Defender for IoT (OT sensor alerts) ----
resource d4iotConnector 'Microsoft.SecurityInsights/dataConnectors@2024-03-01' = if (!empty(defenderForIotSubscriptionId)) {
  scope: law
  name: guid(law.id, 'd4iot')
  kind: 'IOT'
  properties: {
    subscriptionId: defenderForIotSubscriptionId
    dataTypes: {
      alerts: {
        state: 'enabled'
      }
    }
  }
}

// Promote D4IoT alerts to incidents
resource d4iotIncidentRule 'Microsoft.SecurityInsights/alertRules@2023-12-01-preview' = if (!empty(defenderForIotSubscriptionId)) {
  scope: law
  name: guid(law.id, 'd4iot-incidents')
  kind: 'MicrosoftSecurityIncidentCreation'
  properties: {
    displayName: 'OT - Create incidents from Defender for IoT alerts'
    enabled: true
    productFilter: 'Azure Security Center for IoT'
  }
}

// ---- Microsoft Defender for Endpoint (IT-side EMS/historian/jump hosts) ----
resource mdeConnector 'Microsoft.SecurityInsights/dataConnectors@2024-03-01' = if (enableMde) {
  scope: law
  name: guid(law.id, 'mde')
  kind: 'MicrosoftDefenderAdvancedThreatProtection'
  properties: {
    tenantId: tenant().tenantId
    dataTypes: {
      alerts: {
        state: 'enabled'
      }
    }
  }
}

resource mdeIncidentRule 'Microsoft.SecurityInsights/alertRules@2023-12-01-preview' = if (enableMde) {
  scope: law
  name: guid(law.id, 'mde-incidents')
  kind: 'MicrosoftSecurityIncidentCreation'
  properties: {
    displayName: 'IT - Create incidents from Defender for Endpoint alerts'
    enabled: true
    productFilter: 'Microsoft Defender Advanced Threat Protection'
  }
}

// ---- Entra ID Identity Protection (training) ----
// Real, zero-extra-cost connector — works on any Entra tier. Risk-detection
// depth (impossible travel, anonymized IP, leaked credentials, etc.) scales
// with Entra ID P1/P2 licensing, but the connector itself produces genuine
// alerts without any additional product deployment. See CLAUDE.md section 3 —
// this is also the data source the planned IT-profile analytics rules
// (impossible travel, MFA disabled on a privileged account) are written against.
resource aadConnector 'Microsoft.SecurityInsights/dataConnectors@2024-03-01' = if (enableXdrTraining) {
  scope: law
  name: guid(law.id, 'aad-identity-protection')
  kind: 'AzureActiveDirectory'
  properties: {
    tenantId: tenant().tenantId
    dataTypes: {
      alerts: {
        state: 'enabled'
      }
    }
  }
}

resource aadIncidentRule 'Microsoft.SecurityInsights/alertRules@2023-12-01-preview' = if (enableXdrTraining) {
  scope: law
  name: guid(law.id, 'aad-incidents')
  kind: 'MicrosoftSecurityIncidentCreation'
  properties: {
    displayName: 'IT - Create incidents from Entra ID Identity Protection alerts'
    enabled: true
    productFilter: 'Azure Active Directory Identity Protection'
  }
}

// ---- Microsoft Defender for Identity (training — prerequisite not yet met) ----
// Deploying this resource does NOT by itself onboard Defender for Identity —
// that requires an MDI sensor installed next to the client tenant's Domain
// Controllers, a manual step this factory cannot provision. Off by default;
// flip enableDefenderForIdentityConnector once that sensor is confirmed live,
// otherwise this connector will sit connected with zero alerts flowing.
resource mdiConnector 'Microsoft.SecurityInsights/dataConnectors@2024-03-01' = if (enableDefenderForIdentityConnector) {
  scope: law
  name: guid(law.id, 'defender-for-identity')
  kind: 'AzureAdvancedThreatProtection'
  properties: {
    tenantId: tenant().tenantId
    dataTypes: {
      alerts: {
        state: 'enabled'
      }
    }
  }
}

resource mdiIncidentRule 'Microsoft.SecurityInsights/alertRules@2023-12-01-preview' = if (enableDefenderForIdentityConnector) {
  scope: law
  name: guid(law.id, 'mdi-incidents')
  kind: 'MicrosoftSecurityIncidentCreation'
  properties: {
    displayName: 'IT - Create incidents from Defender for Identity alerts'
    enabled: true
    productFilter: 'Azure Advanced Threat Protection'
  }
}

// ---- Microsoft Defender for Cloud Apps / MCAS (training — prerequisite not yet met) ----
// Deploying this resource does NOT by itself onboard Defender for Cloud Apps —
// that requires the product licensed and its Conditional Access App Control /
// OAuth app connectors configured at the client tenant, a manual step this
// factory cannot provision. Off by default; flip
// enableDefenderForCloudAppsConnector once that onboarding is confirmed live,
// otherwise this connector will sit connected with zero alerts flowing.
resource mcasConnector 'Microsoft.SecurityInsights/dataConnectors@2024-03-01' = if (enableDefenderForCloudAppsConnector) {
  scope: law
  name: guid(law.id, 'defender-for-cloud-apps')
  kind: 'MicrosoftCloudAppSecurity'
  properties: {
    tenantId: tenant().tenantId
    dataTypes: {
      alerts: {
        state: 'enabled'
      }
      discoveryLogs: {
        state: 'enabled'
      }
    }
  }
}

resource mcasIncidentRule 'Microsoft.SecurityInsights/alertRules@2023-12-01-preview' = if (enableDefenderForCloudAppsConnector) {
  scope: law
  name: guid(law.id, 'mcas-incidents')
  kind: 'MicrosoftSecurityIncidentCreation'
  properties: {
    displayName: 'IT - Create incidents from Defender for Cloud Apps alerts'
    enabled: true
    productFilter: 'Microsoft Cloud App Security'
  }
}
