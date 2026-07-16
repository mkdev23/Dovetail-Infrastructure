// Incident notification playbook (Logic App) + automation rule that fires it.
// The playbook POSTs the incident JSON to a configurable webhook — point it at
// Teams, Slack, or an internal endpoint (e.g. an AI triage pipeline) per enclave.
// No per-connector OAuth dance = deployable unattended by the factory.
targetScope = 'resourceGroup'

param enclaveName string
param location string
param workspaceName string

@description('Webhook URL that receives High/Medium incident notifications. Empty = skip playbook + automation rule.')
@secure()
param notificationWebhookUrl string = ''

var playbookName = 'pb-dc-${enclaveName}-notify'

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource playbook 'Microsoft.Logic/workflows@2019-05-01' = if (!empty(notificationWebhookUrl)) {
  name: playbookName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        webhookUrl: {
          type: 'String'
          defaultValue: notificationWebhookUrl
        }
      }
      triggers: {
        Microsoft_Sentinel_incident: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {}
          }
        }
      }
      actions: {
        Post_to_webhook: {
          type: 'Http'
          runAfter: {}
          inputs: {
            method: 'POST'
            uri: '@parameters(\'webhookUrl\')'
            headers: {
              'Content-Type': 'application/json'
            }
            body: {
              enclave: enclaveName
              source: 'sentinel'
              incident: '@triggerBody()'
            }
          }
        }
      }
      outputs: {}
    }
  }
}

// Grant the playbook's managed identity Sentinel Responder on the workspace RG
// so automation rules can invoke it and it can read incident context.
var sentinelResponderRole = '3e150937-b8fe-4cfb-8069-0eaf05ecd056'

resource playbookRbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(notificationWebhookUrl)) {
  name: guid(resourceGroup().id, playbookName, sentinelResponderRole)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', sentinelResponderRole)
    principalId: playbook.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output playbookId string = !empty(notificationWebhookUrl) ? playbook.id : ''
output playbookName string = !empty(notificationWebhookUrl) ? playbookName : ''
