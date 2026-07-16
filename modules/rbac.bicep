// Enclave-user RBAC. Scoped to the enclave resource group ONLY.
// Enclave users get visibility into their own workspace and nothing else —
// under Option A there is no tenant trust to traverse even if this is misconfigured.
targetScope = 'resourceGroup'

@description('Object ID of the enclave Entra group (customer analysts / ministry staff)')
param principalId string

@description('Built-in role: Microsoft Sentinel Reader. Swap to Responder (3e150937-b8fe-4cfb-8069-0eaf05ecd056) if enclave staff work incidents.')
param roleDefinitionGuid string = '8d289c81-5878-46d4-8554-54e1e3d8b5cb'

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, principalId, roleDefinitionGuid)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionGuid)
    principalId: principalId
    principalType: 'Group'
  }
}
