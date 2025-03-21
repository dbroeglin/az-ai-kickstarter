metadata name = 'az-ai-kickstarter'
metadata description = 'Deploys the infrastructure for Azure AI App Kickstarter'
metadata author = 'AI GBB EMEA <eminkevich@microsoft.com>'

/* -------------------------------------------------------------------------- */
/*                                 PARAMETERS                                 */
/* -------------------------------------------------------------------------- */

@minLength(1)
@maxLength(64)
@description('Name of the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@description('Principal ID of the user running the deployment')
param azurePrincipalId string

@description('Extra tags to be applied to provisioned resources')
param extraTags object = {}

@description('Location for all resources')
param location string = resourceGroup().location

/* ------------ Optional externally provided model configuration ------------ */

@description('Optional. Externally provided model end point')
param plannerEndpointParam string = ''

@description('Optional. Externally provided model deployment name')
param plannerDeploymentNameParam string = ''

@description('Optional. Externally provided model API version')
param plannerApiVersionParam string = ''

@description('Optional. Externally provided model key')
param plannerKeyParam string = ''

/* ---------------------------- Shared Resources ---------------------------- */

@maxLength(63)
@description('Name of the log analytics workspace to deploy. If not specified, a name will be generated. The maximum length is 63 characters.')
param logAnalyticsWorkspaceName string = ''

@maxLength(255)
@description('Name of the application insights to deploy. If not specified, a name will be generated. The maximum length is 255 characters.')
param applicationInsightsName string = ''

@description('Application Insights Location')
param appInsightsLocation string = location

@description('Activate authentication if true. Defaults to false.')
param useAuthentication bool = false

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

@description('The auth tenant id for the frontend and backend app (leave blank in AZD to use your current tenant)')
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

@description('Azure OpenAI API Version')
var azureOpenAiApiVersion = '2024-12-01-preview'

// ------------------------
// Order is important:
// 1. Executor
// 2. Utility
// 3. Planner (not implemented yet)
@description('Model deployment configurations')
var deployments = [
  {
    name: 'gpt-4o-2024-11-20'
    sku: {
      name: 'GlobalStandard'
      capacity: 50
    }
    model: {
      format: 'OpenAI'
      name: 'gpt-4o'
      version: '2024-11-20'
    }
    versionUpgradeOption: 'OnceCurrentVersionExpired'
  }
  {
    name: 'gpt-4o-mini-2024-07-18'
    sku: {
      name: 'GlobalStandard'
      capacity: 50
    }
    model: {
      format: 'OpenAI'
      name: 'gpt-4o-mini'
      version: '2024-07-18'
    }
    versionUpgradeOption: 'OnceCurrentVersionExpired'
  }
  // {
  //   name: 'o3-mini-2025-01-31'
  //   sku: {
  //     name: 'GlobalStandard'
  //     capacity: 50
  //   }
  //   model: {
  //     format: 'OpenAI'
  //     name: 'o3-mini'
  //     version: '2025-01-31'
  //   }
  //   versionUpgradeOption: 'OnceCurrentVersionExpired'
  // }
]

var azureOpenAiApiEndpoint = azureOpenAi.outputs.endpoint
var executorAzureOpenAiDeploymentName = deployments[0].name
var utilityAzureOpenAiDeploymentName = deployments[1].name

var plannerAzureOpenAiApiVersion = empty(plannerApiVersionParam) ? '2024-12-01-preview' : plannerApiVersionParam
var plannerAzureOpenAiApiEndpoint = empty(plannerEndpointParam) ? azureOpenAi.outputs.endpoint : plannerEndpointParam
var plannerAzureOpenAiDeploymentName = empty(plannerDeploymentNameParam)
  ? deployments[0].name
  : plannerDeploymentNameParam

/* --------------------- Globally Unique Resource Names --------------------- */

// These resources require globally unique names
var _storageAccountName = take(
  '${abbreviations.storageStorageAccounts}${alphaNumericEnvironmentName}${resourceToken}',
  24
)
var _containerRegistryName = !empty(containerRegistryName)
  ? containerRegistryName
  : take('${abbreviations.containerRegistryRegistries}${alphaNumericEnvironmentName}${resourceToken}', 50)
var _keyVaultName = take('${abbreviations.keyVaultVaults}${alphaNumericEnvironmentName}-${resourceToken}', 24)
var _azureOpenAiName = take(
  '${abbreviations.cognitiveServicesOpenAI}${alphaNumericEnvironmentName}${resourceToken}',
  63
)
var _aiSearchServiceName = take('${abbreviations.searchSearchServices}${environmentName}-${resourceToken}', 60)

// These resources only require uniqueness within their scope/resource group
var _applicationInsightsName = !empty(applicationInsightsName)
  ? applicationInsightsName
  : take('${abbreviations.insightsComponents}${environmentName}', 255)
var _logAnalyticsWorkspaceName = !empty(logAnalyticsWorkspaceName)
  ? logAnalyticsWorkspaceName
  : take('${abbreviations.operationalInsightsWorkspaces}${environmentName}', 63)
var _aiHubName = take('${abbreviations.aiPortalHub}${environmentName}', 260)
var _aiProjectName = take('${abbreviations.aiPortalProject}${environmentName}', 260)
var _containerAppsEnvironmentName = !empty(containerAppsEnvironmentName)
  ? containerAppsEnvironmentName
  : take('${abbreviations.appManagedEnvironments}${environmentName}', 60)

/* ----------------------------- Resource Names ----------------------------- */

// These resources only require uniqueness within resource group
var _frontendIdentityName = take(
  '${abbreviations.managedIdentityUserAssignedIdentities}frontend-${environmentName}',
  32
)
var _frontendContainerAppName = !empty(frontendContainerAppName)
  ? frontendContainerAppName
  : take('${abbreviations.appContainerApps}frontend-${environmentName}', 32)
var _backendIdentityName = take('${abbreviations.managedIdentityUserAssignedIdentities}backend-${environmentName}', 32)
var _backendContainerAppName = !empty(backendContainerAppName)
  ? backendContainerAppName
  : take('${abbreviations.appContainerApps}backend-${environmentName}', 32)

/* -------------------------------------------------------------------------- */
/*                                  RESOURCES                                 */
/* -------------------------------------------------------------------------- */

/* -------------------------------- AI Infra  ------------------------------- */

module hub 'modules/ai/hub.bicep' = {
  name: 'hub'
  params: {
    location: location
    tags: tags
    name: _aiHubName
    displayName: _aiHubName
    keyVaultId: keyVault.outputs.resourceId
    storageAccountId: storageAccount.outputs.resourceId
    containerRegistryId: containerRegistry.outputs.resourceId
    applicationInsightsId: appInsightsComponent.outputs.resourceId
    openAiName: azureOpenAi.outputs.name
    openAiConnectionName: 'aoai-connection'
    openAiContentSafetyConnectionName: 'aoai-content-safety-connection'
    aiSearchName: searchService.outputs.name
    aiSearchConnectionName: 'search-service-connection'
  }
}

module project 'modules/ai/project.bicep' = {
  name: 'project'
  params: {
    location: location
    tags: tags
    name: _aiProjectName
    displayName: _aiProjectName
    hubName: hub.outputs.name
  }
}

module storageAccount 'br/public:avm/res/storage/storage-account:0.18.2' = {
  name: 'storageAccount'
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
              principalId: backendIdentity.outputs.principalId
              principalType: 'ServicePrincipal'
            }
          ]
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

module azureOpenAi 'modules/ai/cognitiveservices.bicep' = {
  name: 'cognitiveServices'
  params: {
    location: location
    tags: tags
    name: _azureOpenAiName
    kind: 'AIServices'
    customSubDomainName: _azureOpenAiName
    deployments: deployments
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
    roleAssignments: [
      {
        roleDefinitionIdOrName: 'Cognitive Services OpenAI User'
        principalId: backendIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
      }
      {
        roleDefinitionIdOrName: 'Cognitive Services OpenAI Contributor'
        principalId: azurePrincipalId
      }
    ]
  }
}

module searchService 'br/public:avm/res/search/search-service:0.9.2' = {
  name: _aiSearchServiceName
  scope: resourceGroup()
  params: {
    location: location
    tags: tags
    name: _aiSearchServiceName
    sku: aiSearchSkuName
  }
}

/* ---------------------------- Observability  ------------------------------ */

module logAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.11.1' = {
  name: 'workspaceDeployment'
  params: {
    name: _logAnalyticsWorkspaceName
    location: location
    tags: tags
    dataRetention: 30
  }
}

module appInsightsComponent 'br/public:avm/res/insights/component:0.6.0' = {
  name: _applicationInsightsName
  params: {
    name: _applicationInsightsName
    location: appInsightsLocation
    workspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
  }
}

/* ------------------------ Common App Resources  -------------------------- */

module containerRegistry 'modules/app/container-registry.bicep' = {
  name: _containerRegistryName
  scope: resourceGroup()
  params: {
    location: location
    pullingIdentityNames: [
      _frontendIdentityName
      _backendIdentityName
    ]
    tags: tags
    name: _containerRegistryName // Changed from using token directly to using the variable
  }
}

module containerAppsEnvironment 'br/public:avm/res/app/managed-environment:0.10.0' = {
  name: 'containerAppsEnvironment'
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

module keyVault 'br/public:avm/res/key-vault/vault:0.12.1' = {
  name: 'keyVault'
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
        principalId: frontendIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
      }
      {
        roleDefinitionIdOrName: 'Key Vault Secrets User'
        principalId: backendIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
      }
      {
        principalId: azurePrincipalId
        roleDefinitionIdOrName: 'Key Vault Administrator'
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

/* ------------------------------ Frontend App ------------------------------ */

module frontendIdentity './modules/app/identity.bicep' = {
  name: 'frontendIdentity'
  scope: resourceGroup()
  params: {
    location: location
    identityName: _frontendIdentityName
  }
}

module frontendApp 'modules/app/container-apps.bicep' = {
  name: 'frontend-container-app'
  scope: resourceGroup()
  params: {
    name: _frontendContainerAppName
    location: location
    tags: tags
    identityId: frontendIdentity.outputs.resourceId
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
      AZURE_CLIENT_ID: frontendIdentity.outputs.clientId
    }
    keyvaultIdentities: useAuthentication
      ? {
          'microsoft-provider-authentication-secret': {
            keyVaultUrl: '${keyVault.outputs.uri}secrets/${authClientSecretName}'
            identity: frontendIdentity.outputs.resourceId
          }
        }
      : {}
  }
}

module frontendContainerAppAuth 'modules/app/container-apps-auth.bicep' = if (useAuthentication) {
  name: 'frontend-container-app-auth-module'
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

module backendIdentity './modules/app/identity.bicep' = {
  name: 'backendIdentity'
  scope: resourceGroup()
  params: {
    location: location
    identityName: _backendIdentityName
  }
}

module backendApp 'modules/app/container-apps.bicep' = {
  name: 'backend-container-app'
  scope: resourceGroup()
  params: {
    name: _backendContainerAppName
    location: location
    tags: tags
    identityId: backendIdentity.outputs.resourceId
    containerAppsEnvironmentName: containerAppsEnvironment.outputs.name
    containerRegistryName: containerRegistry.outputs.name
    exists: backendExists
    serviceName: 'backend' // Must match the service name in azure.yaml
    externalIngressAllowed: true // Set to true if you intend to call backend from the locallly deployed frontend
    // Setting to true will allow traffic from anywhere
    env: {
      // Required for container app daprAI
      APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsComponent.outputs.connectionString
      AZURE_RESOURCE_GROUP: resourceGroup().name
      SEMANTICKERNEL_EXPERIMENTAL_GENAI_ENABLE_OTEL_DIAGNOSTICS: true
      SEMANTICKERNEL_EXPERIMENTAL_GENAI_ENABLE_OTEL_DIAGNOSTICS_SENSITIVE: true // OBS! You might want to remove this in production

      // Required for managed identity
      AZURE_CLIENT_ID: backendIdentity.outputs.clientId

      AZURE_OPENAI_API_VERSION: azureOpenAiApiVersion
      AZURE_OPENAI_ENDPOINT: azureOpenAiApiEndpoint
      EXECUTOR_AZURE_OPENAI_DEPLOYMENT_NAME: executorAzureOpenAiDeploymentName
      UTILITY_AZURE_OPENAI_DEPLOYMENT_NAME: utilityAzureOpenAiDeploymentName

      PLANNER_AZURE_OPENAI_ENDPOINT: plannerAzureOpenAiApiEndpoint
      PLANNER_AZURE_OPENAI_API_VERSION: plannerAzureOpenAiApiVersion
      PLANNER_AZURE_OPENAI_DEPLOYMENT_NAME: plannerAzureOpenAiDeploymentName
    }
    secrets: union(
      {},
      empty(plannerKeyParam)
        ? {}
        : {
            plannerkeysecret: plannerKeyParam
          }
    )
  }
}

/* -------------------------------------------------------------------------- */
/*                                   OUTPUTS                                  */
/* -------------------------------------------------------------------------- */

// These outputs are automatically saved in the local azd environment .env file.
// To see these outputs, run `azd env get-values` or
// `azd env get-values --output json` for json output.
// To generate your own `.env` file run `azd env get-values > .env`

/* --------------------------- Infrastructure Resources --------------------- */

@description('The endpoint of the container registry used for image storage and deployment.')
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerRegistry.outputs.loginServer

@description('Application Insights name - Use this to locate your application logs in the Azure portal')
output AZURE_APPLICATION_INSIGHTS_NAME string = appInsightsComponent.outputs.name

@description('Log Analytics Workspace name - Use this to query application logs and metrics')
output AZURE_LOG_ANALYTICS_WORKSPACE_NAME string = logAnalyticsWorkspace.outputs.name

@description('Application Insights connection string - Required for local development to send telemetry')
output APPLICATIONINSIGHTS_CONNECTION_STRING string = appInsightsComponent.outputs.connectionString

/* ---------------------------- App Service Endpoints ----------------------- */

@description('Endpoint URL of the Frontend service - This is the main application URL for end users')
output SERVICE_FRONTEND_URL string = frontendApp.outputs.URL

@description('Endpoint URL of the Backend service - Used by the frontend to make API calls')
output SERVICE_BACKEND_URL string = backendApp.outputs.URL

/* ------------------------ Authentication & RBAC -------------------------- */

@description('Indicates if authentication is enabled for the application')
output USE_AUTHENTICATION bool = useAuthentication

@description('ID of the tenant we are deploying to - Required for authentication flows')
output AZURE_AUTH_TENANT_ID string = authTenantId

@description('Principal ID of the user running the deployment - Has admin rights to deployed resources')
output AZURE_PRINCIPAL_ID string = azurePrincipalId

@description('Application registration client ID - Used by the application for auth flows')
output AZURE_CLIENT_APP_ID string = authClientId

/* ------------------------------ OpenAI Models ----------------------------- */

@description('Azure OpenAI endpoint - Base URL for API calls to Azure OpenAI')
output AZURE_OPENAI_ENDPOINT string = azureOpenAiApiEndpoint

@description('Azure OpenAI API Version - API version to use when calling Azure OpenAI')
output AZURE_OPENAI_API_VERSION string = azureOpenAiApiVersion

@description('Azure OpenAI Model Deployment Name - Executor Service - Used for primary AI operations')
output EXECUTOR_AZURE_OPENAI_DEPLOYMENT_NAME string = executorAzureOpenAiDeploymentName

@description('Azure OpenAI Model Deployment Name - Utility Service - Used for secondary AI operations')
output UTILITY_AZURE_OPENAI_DEPLOYMENT_NAME string = utilityAzureOpenAiDeploymentName

@description('Azure OpenAI Model Deployment Name: Planner - Used for planning operations')
output PLANNER_AZURE_OPENAI_DEPLOYMENT_NAME string = plannerAzureOpenAiDeploymentName

@description('Azure OpenAI endpoint: Planner - URL for planner-specific API calls')
output PLANNER_AZURE_OPENAI_ENDPOINT string = plannerAzureOpenAiApiEndpoint

@description('Azure OpenAI API Version: Planner - API version for planner operations')
output PLANNER_AZURE_OPENAI_API_VERSION string = plannerAzureOpenAiApiVersion

@description('Azure OpenAI Key: Planner - Key for planner operations (empty if using default)')
output plannerkeysecret string = plannerKeyParam

/* -------------------------- Diagnostic Settings --------------------------- */

@description('Semantic Kernel Diagnostics - Controls whether telemetry is enabled')
output SEMANTICKERNEL_EXPERIMENTAL_GENAI_ENABLE_OTEL_DIAGNOSTICS bool = true

@description('Semantic Kernel Diagnostics: Controls whether message content is traced. SECURITY NOTICE: Set to false in production to protect sensitive data')
output SEMANTICKERNEL_EXPERIMENTAL_GENAI_ENABLE_OTEL_DIAGNOSTICS_SENSITIVE bool = true
