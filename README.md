# Welcome to the API Proxy Template
Here is a quick getting started guide to help you get started.

## Prerequisites
- The scripts used to manage your APIs require powershell, please make sure you have the latest version of powershell installed.

- You will need to have access to an Azure subscription, resource groups, and APIM service instance.

- You will need to login to azure and set your powershell context using the ```Connect-AzAccount``` powershell comandlet.  

## Quick Start
1. Clone the repository to your local machine.
2. Update the api-list.json file with the APIs you want to Deploy or Extract
3. Open a powershell terminal window and execute ```Connect-AzAccount``` to login to your Azure account.
4. In the powershell terminal window, navigate to the src/apis folder and execute the apiops.ps1 script with the appropriate parameters to deploy or extract the APIs.

## Overview
The template is designed to simplify the process of creating and managing APIs in Azure API Management.  The template is designed to be used with the Azure API Management service and is designed to be used with the Azure Powershell.

**File Folder Descriptions**
The template will create an manage apis in a folder structure that looks like:

```plaintext
\
|---src
    |---apis
        |---demo-conference-api
            |---GetSession-policy.xml
            |---policy.xml
            |---swagger.json
        |---api-list.json
        |---apiops.ps1
    |---api-backend
        |---readme.md
```

| Folder | Description |
| ------ | ----------- |
| src\api-backend | Where you can put your API. |
| src\api-backend\readme.md | Readme explaining that we are using the sample conference API as a demo. |
| src\apis | Contains one or more api proxies that will be deployed to Azure Api Management. |
| src\apis\demo-conference-api| Contains the proxy definition for the conference api |
| src\apis\demo-conference-api\GetSession-policy.xml | Contains the XML policy for the GetSession operation |
| src\apis\demo-conference-api\policy.xml | Contains the XML policy for the conference api |
| src\apis\demo-conference-api\swagger.json | Contains the swagger definition for the conference api |
| src\apis\api-list.json | Tracking file for the APIs, also denotes which APIs should be extracted |
| src\apis\apiops.ps1 | Deployment \ Extraction script for the APIs |

However, the apis folder can be moved to any location in the repository depending on your needs.  But, the  structure within the apis folder is maintained by the script and should not be changed.

**api-list.json**

The api-list.json file is used to track the APIs that are deployed to the APIM instance.  It also denotes which APIs should be extracted.  The file is in JSON format and contains the following fields: api-name, folder-name, api-path.  The api-name is the name of the API in APIM.  The folder-name is the name of the folder in the apis folder.  The api-path is the path used to access the API in APIM.  So if you APIM instance is at https://myapim.azure-api.net and the api-path is /conference, then the API can be accessed at https://myapim.azure-api.net/conference.

```json
[
    {
        "api-name": "demo-conference-api",
        "folder-name": "demo-conference-api",
        "api-path": "demo"
    }
]
```

**apiops.ps1**

This is the script that will be used to deploy and extract APIs to/from Azure API Management.  The script also supports workspaces.

The parameters for the script are as follows:

| Parameter | Description |
| --------- | ----------- |
| resourceGroup | The name of the resource group where the APIM instance is deployed |
| apimServiceName | The name of the APIM instance |
| subscriptionId | The subscription id where the APIM instance is deployed |
| workspaceName | (Optional) The name of the workspace to deploy the api to.  If no workspace is defined, the api will be deployed to the root APIM instance. |
| restApiVersion | Allows you to specify the version of the Azure Management APIs to use.  It will default to 2023-05-01-preview, which is the version that the script was tested with and the version that supports workspaces |
| scriptFunction | Tell the script to deploy or extract the api.  The options are 'Deploy' or 'Extract' |

here is an example of how to run the script against an APIM instance:

```powershell
.\apiops.ps1 -resourceGroup "myResourceGroup" -apimServiceName "myApim" -subscriptionId "mySubscriptionId" -restApiVersion "2023-05-01-preview" -scriptFunction "Deploy"
```
here is an example of how to run the script against an APIM workspace:

```powershell
.\apiops.ps1 -resourceGroup "myResourceGroup" -apimServiceName "myApim" -subscriptionId "mySubscriptionId" -workspaceName "myWorkspace" -restApiVersion "2023-05-01-preview" -scriptFunction "Deploy"
```


## Deploying and Extracting the Demo API
To get a feel for the template, we have included a sample conference API that you can deploy to your APIM instance.  The API is a simple API that allows you to get a list of sessions for a conference.  The API is defined in the src\api-backend folder and the proxy definition is in the src\apis\demo-conference-api folder.

**Deploying the API**

To deploy the API to your APIM instance, simply run the apiops.ps1 script with the -scriptFunction parameter set to "Deploy".  The script will deploy the API to your APIM instance and create the necessary policies and operations.

Note: if you are deploying to a workspace, make sure to include the -workspaceName parameter.

```powershell
.\apiops.ps1 -resourceGroup "myResourceGroup" -apimServiceName "myApim" -subscriptionId "mySubscriptionId" -restApiVersion "2023-05-01-preview" -scriptFunction "Deploy"
```

**Extracting the API**

To test the extraction process, delete the demo-conference-api folder from the apis folder and run the apiops.ps1 script with the -scriptFunction parameter set to "Extract".  The script will extract the API from your APIM instance and create the necessary files in the apis folder.

Note: if you are deploying to a workspace, make sure to include the -workspaceName parameter.

```powershell
.\apiops.ps1 -resourceGroup "myResourceGroup" -apimServiceName "myApim" -subscriptionId "mySubscriptionId" -restApiVersion "2023-05-01-preview" -scriptFunction "Extract"
```