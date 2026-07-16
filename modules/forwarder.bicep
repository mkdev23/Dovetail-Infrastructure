// Egress/forwarder server — cloud twin of the LEC on-prem egress server.
// In production LEC topology this box is PHYSICAL, sits behind the Waterfall
// data diode, and is onboarded via Azure Arc (see docs/LEC-REFERENCE-ARCHITECTURE.md).
// This module deploys the same build as an Azure VM for dev/demo so the full
// pipeline (rsyslog disk buffering -> AMA -> DCRs -> Sentinel) can be exercised
// end-to-end without hardware. The cloud-init here IS the prod build doc.
targetScope = 'resourceGroup'

param enclaveName string
param location string
param dcrWinSecId string
param dcrSyslogId string
param dcrCefId string

@description('Admin SSH public key for the forwarder VM')
param adminSshPublicKey string

@description('CIDR allowed to send syslog to the forwarder (OT DMZ / sensor subnet). Dev default is the vnet itself.')
param syslogSourceCidr string = '10.90.0.0/24'

param adminUsername string = 'dcadmin'
param vmSize string = 'Standard_B2s'

var vnetName = 'vnet-dc-${enclaveName}'
var vmName = 'fwd-dc-${enclaveName}-01'

var cloudInit = '''
#cloud-config
package_update: true
packages:
  - rsyslog
write_files:
  # Disk-assisted queue: survives uplink outages (Monrovia reality).
  # Buffers up to 8GB on disk, drains automatically when the link returns.
  - path: /etc/rsyslog.d/10-dovetail-buffer.conf
    content: |
      module(load="imudp")
      module(load="imtcp")
      input(type="imudp" port="514")
      input(type="imtcp" port="514")
      main_queue(
        queue.type="LinkedList"
        queue.filename="dovetail_buffer"
        queue.maxdiskspace="8g"
        queue.saveonshutdown="on"
        queue.timeoutenqueue="0"
      )
      # Forward everything to AMA's local CEF/syslog listener
      *.* @@127.0.0.1:28330;RSYSLOG_SyslogProtocol23Format
runcmd:
  - systemctl restart rsyslog
  - sysctl -w net.core.rmem_max=26214400
'''

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-${vmName}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-syslog-from-ot-dmz'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: syslogSourceCidr
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '514'
        }
      }
      {
        name: 'deny-all-other-inbound'
        properties: {
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [ '10.90.0.0/24' ]
    }
    subnets: [
      {
        name: 'snet-forwarder'
        properties: {
          addressPrefix: '10.90.0.0/26'
          networkSecurityGroup: { id: nsg.id }
        }
      }
    ]
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: 'nic-${vmName}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: { id: vnet.properties.subnets[0].id }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: vmName
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    hardwareProfile: { vmSize: vmSize }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      customData: base64(cloudInit)
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminSshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'StandardSSD_LRS' }
        diskSizeGB: 64 // room for the 8GB rsyslog disk buffer + headroom
      }
    }
    networkProfile: {
      networkInterfaces: [ { id: nic.id } ]
    }
  }
}

resource ama 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = {
  parent: vm
  name: 'AzureMonitorLinuxAgent'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorLinuxAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
  }
}

// Associate the forwarder to all three enclave DCRs
resource assocSyslog 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = {
  name: 'dcra-${enclaveName}-syslog'
  scope: vm
  properties: { dataCollectionRuleId: dcrSyslogId }
}

resource assocCef 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = {
  name: 'dcra-${enclaveName}-cef'
  scope: vm
  properties: { dataCollectionRuleId: dcrCefId }
}

resource assocWin 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = {
  name: 'dcra-${enclaveName}-winsec'
  scope: vm
  properties: { dataCollectionRuleId: dcrWinSecId }
}

output forwarderVmName string = vm.name
output forwarderPrivateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
