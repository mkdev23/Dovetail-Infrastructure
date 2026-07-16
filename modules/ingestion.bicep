// Data Collection Endpoint + Data Collection Rules per enclave.
// Filtering happens HERE, at collection time — standing rule for this
// deployment given Monrovia uplink constraints and ingestion cost.
targetScope = 'resourceGroup'

param enclaveName string
param location string
param workspaceResourceId string
param tags object

resource dce 'Microsoft.Insights/dataCollectionEndpoints@2022-06-01' = {
  name: 'dce-dc-${enclaveName}'
  location: location
  tags: tags
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

// ------------------------------------------------------------
// DCR 1 — Windows Security Events (curated, not "all events")
// High-value auth / privilege / persistence / lateral-movement IDs.
// Extend the xPath deliberately; never fall back to Security!*.
// ------------------------------------------------------------
resource dcrWinSec 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: 'dcr-dc-${enclaveName}-winsec'
  location: location
  tags: tags
  properties: {
    dataCollectionEndpointId: dce.id
    dataSources: {
      windowsEventLogs: [
        {
          name: 'winSecurityCurated'
          streams: [ 'Microsoft-SecurityEvent' ]
          xPathQueries: [
            'Security!*[System[(EventID=1102) or (EventID=4624) or (EventID=4625) or (EventID=4648) or (EventID=4657) or (EventID=4672) or (EventID=4688) or (EventID=4697) or (EventID=4698) or (EventID=4719) or (EventID=4720) or (EventID=4722) or (EventID=4724) or (EventID=4728) or (EventID=4732) or (EventID=4740) or (EventID=4756) or (EventID=4768) or (EventID=4769) or (EventID=4771) or (EventID=4776) or (EventID=5140) or (EventID=7045)]]'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'enclaveWorkspace'
          workspaceResourceId: workspaceResourceId
        }
      ]
    }
    dataFlows: [
      {
        streams: [ 'Microsoft-SecurityEvent' ]
        destinations: [ 'enclaveWorkspace' ]
      }
    ]
  }
}

// ------------------------------------------------------------
// DCR 2 — Linux Syslog (forwarder + local Linux hosts)
// Warning-and-above only for chatty facilities.
// ------------------------------------------------------------
resource dcrSyslog 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: 'dcr-dc-${enclaveName}-syslog'
  location: location
  tags: tags
  properties: {
    dataCollectionEndpointId: dce.id
    dataSources: {
      syslog: [
        {
          name: 'syslogAuth'
          streams: [ 'Microsoft-Syslog' ]
          facilityNames: [ 'auth', 'authpriv' ]
          logLevels: [ 'Debug', 'Info', 'Notice', 'Warning', 'Error', 'Critical', 'Alert', 'Emergency' ]
        }
        {
          name: 'syslogGeneral'
          streams: [ 'Microsoft-Syslog' ]
          facilityNames: [ 'daemon', 'kern', 'syslog' ]
          logLevels: [ 'Warning', 'Error', 'Critical', 'Alert', 'Emergency' ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'enclaveWorkspace'
          workspaceResourceId: workspaceResourceId
        }
      ]
    }
    dataFlows: [
      {
        streams: [ 'Microsoft-Syslog' ]
        destinations: [ 'enclaveWorkspace' ]
      }
    ]
  }
}

// ------------------------------------------------------------
// DCR 3 — CEF (firewalls / network security appliances via forwarder)
// transformKql drops obvious noise before it crosses the uplink.
// Tune the drop list per client appliance during onboarding.
// ------------------------------------------------------------
resource dcrCef 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: 'dcr-dc-${enclaveName}-cef'
  location: location
  tags: tags
  properties: {
    dataCollectionEndpointId: dce.id
    dataSources: {
      syslog: [
        {
          name: 'cefSources'
          streams: [ 'Microsoft-CommonSecurityLog' ]
          facilityNames: [ 'local0', 'local1', 'local2', 'local3', 'local4' ]
          logLevels: [ 'Debug', 'Info', 'Notice', 'Warning', 'Error', 'Critical', 'Alert', 'Emergency' ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'enclaveWorkspace'
          workspaceResourceId: workspaceResourceId
        }
      ]
    }
    dataFlows: [
      {
        streams: [ 'Microsoft-CommonSecurityLog' ]
        destinations: [ 'enclaveWorkspace' ]
        // Example noise drop — allowed intra-zone traffic logs add volume, not signal.
        transformKql: 'source | where not(DeviceAction =~ "allow" and LogSeverity in ("0","1","2"))'
      }
    ]
  }
}

output dceId string = dce.id
output dceLogsIngestionEndpoint string = dce.properties.logsIngestion.endpoint
output dcrWinSecId string = dcrWinSec.id
output dcrSyslogId string = dcrSyslog.id
output dcrCefId string = dcrCef.id
