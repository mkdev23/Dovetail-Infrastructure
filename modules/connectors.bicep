// Sentinel data connectors for the LEC-style OT profile.
// Defender for IoT alerts + Microsoft Defender for Endpoint, plus the
// Microsoft-security incident-creation rules that promote their alerts
// to Sentinel incidents in the enclave workspace.
targetScope = 'resourceGroup'

param workspaceName string

@description('Subscription ID where Defender for IoT is enabled for this enclave (usually the enclave subscription itself). Empty = skip D4IoT connector.')
param defenderForIotSubscriptionId string = ''

@description('Enable the Microsoft Defender for Endpoint connector (IT-side servers/workstations)')
param enableMde bool = true

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
