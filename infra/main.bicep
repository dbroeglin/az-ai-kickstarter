metadata name = 'az-ai-kickstarter'
metadata description = 'Deploys the infrastructure for Azure AI App Kickstarter'
metadata author = 'AI GBB EMEA <eminkevich@microsoft.com>; <dobroegl@microsoft.com>'

/* -------------------------------------------------------------------------- */
/*                                 PARAMETERS                                 */
/* -------------------------------------------------------------------------- */

@minLength(1)
@maxLength(64)
@description('Name of the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@description('Principal ID of the user running the deployment')
param azurePrincipalId string

@description('Location for all resources')
param location string = resourceGroup().location

@description('Extra tags to be applied to provisioned resources')
param extraTags object = {}

/* ------------------------ Feature flag parameters ------------------------ */

@description('If true, deploy Azure AI Search Service')
param useAiSearchService bool = false

@description('If true, use and setup authentication with Azure Entra ID')
param useAuthentication bool = false

@description('Set to true to use an existing Azure OpenAI service.In that case you will need to provide azureOpenAiEndpoint, azureOpenAiApiVersion, executorAzureOpenAiDeploymentName and utilityAzureOpenAiDeploymentName. Defaults to false.')
param useExistingAzureOpenAi bool = false

@description('Set to true to use an existing Azure AI Search service.In that case you will need to provide TODO. Defaults to false.')
param useExistingAiSearchService bool = false


/* -------- Optional externally provided Azure OpenAI configuration -------- */

@description('Optional. The name of the Azure OpenAI resource to reuse. Used only if useExistingAzureOpenAi is true.')
param azureOpenAiName string = ''

@description('Optional. The endpoint of the Azure OpenAI resource to reuse. Used only if useExistingAzureOpenAi is true.')
param azureOpenAiEndpoint string = ''

@description('Optional. The API version of the Azure OpenAI resource to reuse. Used only if useExistingAzureOpenAi is true.')
param azureOpenAiApiVersion string = ''

@description('Optional. The name of the Azure OpenAI deployment for the executor to reuse. Used only if useExistingAzureOpenAi is true.')
param executorAzureOpenAiDeploymentName string = ''

@description('Optional. The name of the Azure OpenAI deployment for the utility to reuse. Used only if useExistingAzureOpenAi is true.')
param utilityAzureOpenAiDeploymentName string = ''

/* ------------ Optional externally provided search service ---------------- */

@description('Optional. Defines the SKU of an Azure AI Search Service, which determines price tier and capacity limits.')
@allowed([
  'basic'
  'free'
  'standard'
  'standard2'
  'standard3'
  'storage_optimized_l1'
  'storage_optimized_l2'
])
param aiSearchSkuName string = 'basic'

@description('Name of the Azure AI Search Service to deploy. If not specified, a name will be generated. The maximum length is 260 characters.')
param aiSearchServiceName string = ''

@description('The Azure Cognitive Search service resource group name to use for the AI Studio Hub Resource. Optional: needed only if aiSearchServiceName is provided and the service is deployed in a different resource group.')
param aiSearchResourceGroupName string = ''

/* ---------------------------- Shared Resources ---------------------------- */

@maxLength(63)
@description('Name of the log analytics workspace to deploy. If not specified, a name will be generated. The maximum length is 63 characters.')
param logAnalyticsWorkspaceName string = ''

@maxLength(255)
@description('Name of the application insights to deploy. If not specified, a name will be generated. The maximum length is 255 characters.')
param applicationInsightsName string = ''

@description('Application Insights Location')
param appInsightsLocation string = location

@description('The auth tenant id for the app (leave blank in AZD to use your current tenant)')
param authTenantId string = '' // Make sure authTenantId is set if not using AZD

@description('Name of the authentication client secret in the key vault')
param authClientSecretName string = 'AZURE-AUTH-CLIENT-SECRET'

@description('The auth client id for the frontend and backend app')
param authClientId string = ''

@description('Client secret of the authentication client')
@secure()
param authClientSecret string = ''

@maxLength(50)
@description('Name of the container registry to deploy. If not specified, a name will be generated. The name is global and must be unique within Azure. The maximum length is 50 characters.')
param containerRegistryName string = ''

@maxLength(60)
@description('Name of the container apps environment to deploy. If not specified, a name will be generated. The maximum length is 60 characters.')
param containerAppsEnvironmentName string = ''

/* -------------------------------- Frontend -------------------------------- */

@maxLength(32)
@description('Name of the frontend container app to deploy. If not specified, a name will be generated. The maximum length is 32 characters.')
param frontendContainerAppName string = ''

@description('Set if the frontend container app already exists.')
param frontendExists bool = false

/* --------------------------------- Backend -------------------------------- */

@maxLength(32)
@description('Name of the backend container app to deploy. If not specified, a name will be generated. The maximum length is 32 characters.')
param backendContainerAppName string = ''

@description('Set if the backend container app already exists.')
param backendExists bool = false

/* -------------------------------------------------------------------------- */
/*                                  VARIABLES                                 */
/* -------------------------------------------------------------------------- */

// Load abbreviations from JSON file
var abbreviations = loadJsonContent('./abbreviations.json')

@description('Generate a unique token to make global resource names unique')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

@description('Name of the environment with only alphanumeric characters. Used for resource names that require alphanumeric characters only')
var alphaNumericEnvironmentName = replace(replace(environmentName, '-', ''), ' ', '')

@description('Tags to be applied to all provisioned resources')
var tags = union(
  {
    'azd-env-name': environmentName
    solution: 'az-ai-kickstarter'
  },
  extraTags
)

/* --------------------- Globally Unique Resource Names --------------------- */

var _applicationInsightsName = !empty(applicationInsightsName)
  ? applicationInsightsName
  : take('${abbreviations.insightsComponents}${environmentName}', 255)
var _logAnalyticsWorkspaceName = !empty(logAnalyticsWorkspaceName)
  ? logAnalyticsWorkspaceName
  : take('${abbreviations.operationalInsightsWorkspaces}${environmentName}', 63)

var _storageAccountName = take(
  '${abbreviations.storageStorageAccounts}${alphaNumericEnvironmentName}${resourceToken}',
  24
)
var _azureOpenAiName = take(
  '${abbreviations.cognitiveServicesOpenAI}${alphaNumericEnvironmentName}${resourceToken}',
  63
)
var _aiHubName = take('${abbreviations.aiPortalHub}${environmentName}', 260)
var _aiProjectName = take('${abbreviations.aiPortalProject}${environmentName}', 260)
var _aiSearchServiceName = empty(aiSearchServiceName)
  ? take('${abbreviations.searchSearchServices}${environmentName}', 260)
  : aiSearchServiceName

var _containerRegistryName = !empty(containerRegistryName)
  ? containerRegistryName
  : take('${abbreviations.containerRegistryRegistries}${alphaNumericEnvironmentName}${resourceToken}', 50)
var _keyVaultName = take('${abbreviations.keyVaultVaults}${alphaNumericEnvironmentName}-${resourceToken}', 24)
var _containerAppsEnvironmentName = !empty(containerAppsEnvironmentName)
  ? containerAppsEnvironmentName
  : take('${abbreviations.appManagedEnvironments}${environmentName}', 60)

/* ----------------------------- Resource Names ----------------------------- */

// These resources only require uniqueness within resource group
var _appIdentityName = take('${abbreviations.managedIdentityUserAssignedIdentities}app-${environmentName}', 32)
var _frontendContainerAppName = !empty(frontendContainerAppName)
  ? frontendContainerAppName
  : take('${abbreviations.appContainerApps}frontend-${environmentName}', 32)
var _backendContainerAppName = !empty(backendContainerAppName)
  ? backendContainerAppName
  : take('${abbreviations.appContainerApps}backend-${environmentName}', 32)
  
// ------------------------
// Order is important:
// 1. Executor
// 2. Utility
@description('Model deployment configurations')
var deployments = loadYamlContent('./deployments.yaml')

var _azureOpenAiEndpoint = useExistingAzureOpenAi ? azureOpenAiEndpoint : aiServices.outputs.endpoint

@description('Azure OpenAI API Version')
var _azureOpenAiApiVersion = empty(azureOpenAiApiVersion) ? '2024-12-01-preview' : azureOpenAiApiVersion

@description('Azure OpenAI Model Deployment Name - Executor Service')
var _executorAzureOpenAiDeploymentName = !empty(executorAzureOpenAiDeploymentName)
  ? executorAzureOpenAiDeploymentName
  : deployments[0].name

@description('Azure OpenAI Model Deployment Name - Utility Service')
var _utilityAzureOpenAiDeploymentName = !empty(utilityAzureOpenAiDeploymentName)
  ? utilityAzureOpenAiDeploymentName
  : deployments[1].name

/* -------------------------------------------------------------------------- */
/*                                  RESOURCES                                 */
/* -------------------------------------------------------------------------- */

/* ------------------------------- AI Foudry  ------------------------------- */

module hub 'modules/ai/hub.bicep' = {
  name: '${deployment().name}-aiHub'
  params: {
    location: location
    tags: tags
    name: _aiHubName
    displayName: _aiHubName
    keyVaultId: keyVault.outputs.resourceId
    storageAccountId: storageAccount.outputs.resourceId
    containerRegistryId: containerRegistry.outputs.resourceId
    applicationInsightsId: appInsightsComponent.outputs.resourceId
    openAiName: useExistingAzureOpenAi ? azureOpenAiName : _azureOpenAiName
    openAiConnectionName: 'aoai-connection'

    aiSearchName: useAiSearchService ? searchService.outputs.name : ''
    aiSearchResourceGroupName: useAiSearchService ? aiSearchResourceGroupName : ''
    aiSearchConnectionName: 'search-service-connection'
  }
}

module project 'modules/ai/project.bicep' = {
  name: '${deployment().name}-aiProject'
  params: {
    location: location
    tags: tags
    name: _aiProjectName
    displayName: _aiProjectName
    hubName: hub.outputs.name
  }
}

module storageAccount 'br/public:avm/res/storage/storage-account:0.19.0' = {
  name: '${deployment().name}-storageAccount'
  scope: resourceGroup()
  params: {
    location: location
    tags: tags
    name: _storageAccountName
    kind: 'StorageV2'
    blobServices: {
      corsRules: [
        {
          allowedOrigins: [
            'https://mlworkspace.azure.ai'
            'https://ml.azure.com'
            'https://*.ml.azure.com'
            'https://ai.azure.com'
            'https://*.ai.azure.com'
            'https://mlworkspacecanary.azure.ai'
            'https://mlworkspace.azureml-test.net'
          ]
          allowedMethods: [
            'GET'
            'HEAD'
            'POST'
            'PUT'
            'DELETE'
            'OPTIONS'
            'PATCH'
          ]
          maxAgeInSeconds: 1800
          exposedHeaders: [
            '*'
          ]
          allowedHeaders: [
            '*'
          ]
        }
      ]
      containers: [
        {
          name: 'default'
          roleAssignments: [
            {
              roleDefinitionIdOrName: 'Storage Blob Data Contributor'
              principalId: appIdentity.outputs.principalId
              principalType: 'ServicePrincipal'
            }
          ]
        }
      ]
      roleAssignments: [
        {
          roleDefinitionIdOrName: 'Storage Blob Data Contributor'
          principalId: azurePrincipalId
        }
      ]
      deleteRetentionPolicy: {
        allowPermanentDelete: false
        enabled: false
      }
      shareDeleteRetentionPolicy: {
        enabled: true
        days: 7
      }
    }
  }
}

module aiServices 'br/public:avm/res/cognitive-services/account:0.10.2' = if (!useExistingAzureOpenAi) {
  name: '${deployment().name}-aiServices'
  params: {
    name: _azureOpenAiName
    location: location
    tags: tags
    kind: 'AIServices'
    customSubDomainName: _azureOpenAiName
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
    disableLocalAuth: false
    sku: 'S0'
    deployments: deployments
    diagnosticSettings: [
      {
        name: 'customSetting'
        logCategoriesAndGroups: [
          {
            category: 'RequestResponse'
          }
          {
            category: 'Audit'
          }
        ]
        metricCategories: [
          {
            category: 'AllMetrics'
          }
        ]
        workspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
      }
    ]
    roleAssignments: [
      {
        roleDefinitionIdOrName: 'Cognitive Services OpenAI User'
        principalId: appIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
      }
      {
        roleDefinitionIdOrName: 'Cognitive Services OpenAI Contributor'
        principalId: azurePrincipalId
      }
    ]
  }
}

module searchService 'br/public:avm/res/search/search-service:0.9.2' = if (useAiSearchService) {
  name: '${deployment().name}-aiSearchService'
  scope: resourceGroup()
  params: {
    name: _aiSearchServiceName
    location: location
    tags: tags
    sku: aiSearchSkuName
    partitionCount: 1
    replicaCount: 1
  }
}

/* ---------------------------- Observability  ------------------------------ */

module logAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.11.1' = {
  name: '${deployment().name}-workspaceDeployment'
  params: {
    name: _logAnalyticsWorkspaceName
    location: location
    tags: tags
    dataRetention: 30
  }
}

module appInsightsComponent 'br/public:avm/res/insights/component:0.6.0' = {
  name: '${deployment().name}-applicationInsights'
  params: {
    name: _applicationInsightsName
    location: appInsightsLocation
    workspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
  }
}

/* ------------------------ Common App Resources  -------------------------- */

module appIdentity './modules/app/identity.bicep' = {
  name: '${deployment().name}-appIdentity'
  scope: resourceGroup()
  params: {
    location: location
    identityName: _appIdentityName
  }
}

module containerRegistry 'br/public:avm/res/container-registry/registry:0.9.1' = {
  name: '${deployment().name}-containerRegistry'
  params: {
    name: _containerRegistryName
    location: location
    tags: tags
    acrSku: 'Standard'
    acrAdminUserEnabled: true
    roleAssignments: [
      {
        roleDefinitionIdOrName: 'AcrPull'
        principalId: appIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
      }
      {
        roleDefinitionIdOrName: 'AcrPull'
        principalId: azurePrincipalId
      }
    ]
  }
}

module keyVault 'br/public:avm/res/key-vault/vault:0.12.1' = {
  name: '${deployment().name}-keyVault'
  scope: resourceGroup()
  params: {
    location: location
    tags: tags
    name: _keyVaultName
    enableRbacAuthorization: true
    enablePurgeProtection: false // Set to true to if you deploy in production and want to protect against accidental deletion
    roleAssignments: [
      {
        roleDefinitionIdOrName: 'Key Vault Secrets User'
        principalId: appIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
      }
      {
        roleDefinitionIdOrName: 'Key Vault Administrator'
        principalId: azurePrincipalId
      }
    ]
    secrets: useAuthentication && authClientSecret != ''
      ? [
          {
            name: authClientSecretName
            value: authClientSecret
          }
        ]
      : []
  }
}

module containerAppsEnvironment 'br/public:avm/res/app/managed-environment:0.10.2' = {
  name: '${deployment().name}-containerAppsEnvironment'
  params: {
    name: _containerAppsEnvironmentName
    location: location
    tags: tags
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
    daprAIConnectionString: appInsightsComponent.outputs.connectionString
    zoneRedundant: false
    publicNetworkAccess: 'Enabled'
  }
}

/* ------------------------------ Frontend App ------------------------------ */

module frontendApp 'modules/app/container-apps.bicep' = {
  name: '${deployment().name}-frontendContainerApp'
  scope: resourceGroup()
  params: {
    name: _frontendContainerAppName
    tags: tags
    identityId: appIdentity.outputs.resourceId
    containerAppsEnvironmentName: containerAppsEnvironment.outputs.name
    containerRegistryName: containerRegistry.outputs.name
    exists: frontendExists
    serviceName: 'frontend' // Must match the service name in azure.yaml
    env: {
      // URL of the backend endpoint, for instance: http://localhost:8000
      BACKEND_ENDPOINT: backendApp.outputs.URL

      // Required for the frontend app to ask for a token for the backend app
      AZURE_CLIENT_APP_ID: authClientId

      // Required for container app daprAI
      APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsComponent.outputs.connectionString

      // Required for managed identity
      AZURE_CLIENT_ID: appIdentity.outputs.clientId
    }
    keyvaultIdentities: useAuthentication
      ? {
          'microsoft-provider-authentication-secret': {
            keyVaultUrl: '${keyVault.outputs.uri}secrets/${authClientSecretName}'
            identity: appIdentity.outputs.resourceId
          }
        }
      : {}
  }
}

module frontendContainerAppAuth 'modules/app/container-apps-auth.bicep' = if (useAuthentication) {
  name: '${deployment().name}-frontendContainerAppAuthModule'
  params: {
    name: frontendApp.outputs.name
    clientId: authClientId
    clientSecretName: 'microsoft-provider-authentication-secret'
    openIdIssuer: '${environment().authentication.loginEndpoint}${authTenantId}/v2.0' // Works only for Microsoft Entra
    unauthenticatedClientAction: 'RedirectToLoginPage'
    allowedApplications: [
      '04b07795-8ddb-461a-bbee-02f9e1bf7b46' // AZ CLI for testing purposes
    ]
  }
}

/* ------------------------------ Backend App ------------------------------- */

module backendApp 'modules/app/container-apps.bicep' = {
  name: '${deployment().name}-backendContainerApp'
  scope: resourceGroup()
  params: {
    name: _backendContainerAppName
    tags: tags
    identityId: appIdentity.outputs.resourceId
    containerAppsEnvironmentName: containerAppsEnvironment.outputs.name
    containerRegistryName: containerRegistry.outputs.name
    exists: backendExists
    serviceName: 'backend' // Must match the service name in azure.yaml
    externalIngressAllowed: false // Set to true if you intend to call backend from the locallly deployed frontend
    // Setting to true will allow traffic from anywhere
    env: {
      // Required for container app daprAI
      APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsComponent.outputs.connectionString
      AZURE_RESOURCE_GROUP: resourceGroup().name
      SEMANTICKERNEL_EXPERIMENTAL_GENAI_ENABLE_OTEL_DIAGNOSTICS: true
      SEMANTICKERNEL_EXPERIMENTAL_GENAI_ENABLE_OTEL_DIAGNOSTICS_SENSITIVE: true // OBS! You might want to remove this in production

      // Required for managed identity
      AZURE_CLIENT_ID: appIdentity.outputs.clientId

      AZURE_OPENAI_API_VERSION: _azureOpenAiApiVersion
      AZURE_OPENAI_ENDPOINT: _azureOpenAiEndpoint
      EXECUTOR_AZURE_OPENAI_DEPLOYMENT_NAME: _executorAzureOpenAiDeploymentName
      UTILITY_AZURE_OPENAI_DEPLOYMENT_NAME: _utilityAzureOpenAiDeploymentName
    }
    secrets: {}
  }
}

/* -------------------------------------------------------------------------- */
/*                                   OUTPUTS                                  */
/* -------------------------------------------------------------------------- */

// Outputs are automatically saved in the local azd environment .env file.
// To see these outputs, run `azd env get-values`,  or
// `azd env get-values --output json` for json output.
// To generate your own `.env` file run `azd env get-values > .env`

/* -------------------------- Feature flags ------------------------------- */

@description('If true, deploy Azure AI Search Service')
output USE_AI_SEARCH bool = useAiSearchService

@description('If true, use and setup authentication with Azure Entra ID')
output USE_AUTHENTICATION bool = useAuthentication

@description('if true, reuse existing Azure OpenAI Service')
output USE_EXISTING_AZURE_OPENAI bool = useExistingAzureOpenAi


/* --------------------------- Apps Deployment ----------------------------- */

@description('The endpoint of the container registry.') // necessary for azd deploy
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerRegistry.outputs.loginServer

@description('Endpoint URL of the Frontend service')
output SERVICE_FRONTEND_URL string = frontendApp.outputs.URL

@description('Endpoint URL of the Backend service')
output SERVICE_BACKEND_URL string = backendApp.outputs.URL

/* ------------------------ Authentication & RBAC ------------------------- */

@description('ID of the tenant we are deploying to')
output AZURE_AUTH_TENANT_ID string = authTenantId

@description('Principal ID of the user running the deployment')
output AZURE_PRINCIPAL_ID string = azurePrincipalId

@description('Application registration client ID')
output AZURE_CLIENT_APP_ID string = authClientId

/* ------------------------------- Models --------------------------------- */

@description('Azure OpenAI endpoint - Base URL for API calls to Azure OpenAI')
output AZURE_OPENAI_ENDPOINT string = _azureOpenAiEndpoint

@description('Azure OpenAI API Version - API version to use when calling Azure OpenAI')
output AZURE_OPENAI_API_VERSION string = _azureOpenAiApiVersion

@description('Azure OpenAI Model Deployment Name - Executor Service')
output EXECUTOR_AZURE_OPENAI_DEPLOYMENT_NAME string = _executorAzureOpenAiDeploymentName

@description('Azure OpenAI Model Deployment Name - Utility Service')
output UTILITY_AZURE_OPENAI_DEPLOYMENT_NAME string = _utilityAzureOpenAiDeploymentName

@description('JSON deployment configuration for the models')
output AZURE_OPENAI_DEPLOYMENTS object[] = deployments

/* -------------------------- Diagnostic Settings --------------------------- */

@description('Application Insights name')
output AZURE_APPLICATION_INSIGHTS_NAME string = appInsightsComponent.outputs.name

@description('Log Analytics Workspace name')
output AZURE_LOG_ANALYTICS_WORKSPACE_NAME string = logAnalyticsWorkspace.outputs.name

@description('Application Insights connection string')
output APPLICATIONINSIGHTS_CONNECTION_STRING string = appInsightsComponent.outputs.connectionString

@description('Semantic Kernel Diagnostics')
output SEMANTICKERNEL_EXPERIMENTAL_GENAI_ENABLE_OTEL_DIAGNOSTICS bool = true

@description('Semantic Kernel Diagnostics: if set, content of the messages is traced. Set to false in production')
output SEMANTICKERNEL_EXPERIMENTAL_GENAI_ENABLE_OTEL_DIAGNOSTICS_SENSITIVE bool = true
