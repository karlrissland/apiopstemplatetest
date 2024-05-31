param(
    [Parameter(Mandatory = $true)]
    [string]$resourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$subscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$apimServiceName,

    [string]$workspaceName = $null,

    [string]$restApiVersion = "2023-05-01-preview",

    [Parameter(Mandatory = $true)]
    [ValidateSet('Deploy','Extract')]
    [string]$scriptFunction,

    #pass in the apilistjson object as a string if you don't want to use the local file
    #any updates to the apilistjson is output to the output variable
    [string]$apilistjsonparam =  $null
)

function getApiExport {
    param(
        [string]$apiName,
        [string]$definitionFormat,
        [string]$folderName
    )

    write-host "---------------------------Getting API Export for $apiName"

    switch ($definitionFormat) {
        "swagger-json" {
            $fileName = "swagger.json"
        }
        "openapi" {
            $fileName = "openapi.yaml"
        }
        "openapi+json" {
            $fileName = "openapi.json"
        }
    }

    $headers = @{
        'Authorization' = "Bearer $accessToken"
    }

    $url = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimServiceName/$($workspaceUrlPart)apis/$apiName"
    $qs = "?format=$definitionFormat&export=true&api-version=$restApiVersion"

    $null = Invoke-RestMethod -Method Get -Uri ($url + $qs) -Headers $headers

    # if json-link was used
    #-------------------------------------
    # $downloadLink = $response.value.link

    # Invoke-WebRequest -Uri $downloadLink -OutFile "./$folderName/$fileName"

    # Response differs if using workspaces or not
    if ([string]::IsNullOrEmpty($workspaceName)) {
        # no workspaces used
        $definitionFileContents = $response.value
    } else {
        # if using workspaces
        $definitionFileContents = $response.properties.value
    }

    $apiPath = $response.value.basePath

    $json = $definitionFileContents | ConvertTo-Json -Depth 100

    set-content -Path "./$folderName/$fileName" -Value $json

    return $apiPath 
}

function getApiPolicy{
    param(
        [string]$apiName,
        [string]$folderName
    )

    write-host "----------------------------Getting API Policy for $apiName"

    $headers = @{
        'Authorization' = "Bearer $accessToken"
    }

    $url = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimServiceName/$($workspaceUrlPart)apis/$apiName/policies/policy"
    $qs = "?api-version=$restApiVersion"

    try{
        $null = Invoke-RestMethod -Method Get -Uri ($url + $qs) -Headers $headers

        $policy = $response.properties.value

        Set-Content -Path "./$folderName/policy.xml" -Value $policy

    }catch{
        Write-Host "No policy found for api $operationName"
    }
}

function getApiOperations{
    param(
        [string]$apiName
    )

    write-host "----------------------------Getting API Operations for $apiName"

    $headers = @{
        'Authorization' = "Bearer $accessToken"
    }

    $url = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimServiceName/$($workspaceUrlPart)apis/$apiName/operations"
    $qs = "?api-version=$restApiVersion"

    $response = Invoke-RestMethod -Method Get -Uri ($url + $qs) -Headers $headers

    $operationNames = @()
    foreach ($operation in $response.value) {
        $operationNames += $operation.name
    }

    return $operationNames
}

function getOperationPolicys{
    param(
        [string]$apiName,
        [string]$folderName
    )

    write-host "----------------------------Getting Operation Policies for $apiName"

    $operationNames = getApiOperations -apiName $apiName

    foreach($operationName in $operationNames){
        $headers = @{
            'Authorization' = "Bearer $accessToken"
        }

        $url = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimServiceName/$($workspaceUrlPart)apis/$apiName/operations/$operationName/policies/policy"
        $qs = "?api-version=$restApiVersion"

        try{
            $response = Invoke-RestMethod -Method Get -Uri ($url + $qs) -Headers $headers

            $policy = $response.properties.value

            if($null -ne $policy){
                Set-Content -Path "./$folderName/$operationName-policy.xml" -Value $policy
            }
        }
        catch{
            Write-Host "----------------------------No policy found for operation $operationName"
        }
    }
}

function putApiImportCreateUpdate{
    param(
        [string]$apiName,
        [string]$folderName,
        [string]$definitionFormat,
        [string]$apiPath
    )

    write-host "----------------------------Putting API Import CreateUpdate for $apiName"

    # Determine what type of definition file we are working with
    switch ($definitionFormat) {
        "swagger-json" {
            $fileName = "swagger.json"
        }
        "openapi" {
            $fileName = "openapi.yaml"
        }
        "openapi+json" {
            $fileName = "openapi.json"
        }
    }

    $contents = Get-Content -Path "./$folderName/$fileName" -Raw
    
    $headers = @{
        'Authorization' = "Bearer $accessToken"
        'Content-Type' = 'application/json'
    }

    $body = "{""properties"": {""format"": ""$definitionFormat"",""value"": $contents,""path"": ""$apiPath""}}"

    $url = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimServiceName/$($workspaceUrlPart)apis/$apiName"
    $qs = "?api-version=$restApiVersion"
    $uri = ($url + $qs)

    $null = Invoke-RestMethod -Method Put -Uri $uri -Headers $headers -Body $body
}

function putApiPolicyCreateUpdate{
    param(
        [string]$apiName,
        [string]$folderName
    )

    write-host "----------------------------Putting API Policy CreateUpdate for $apiName"

    $contents = Get-Content -Path "./$folderName/policy.xml" -Raw

    $contents = $contents -replace "`r`n", ""

    $headers = @{
        'Authorization' = "Bearer $accessToken"
        'Content-Type' = 'application/json'
    }

    $body = "{""properties"": { ""format"": ""xml"", ""value"": ""$contents""}}"

    $url = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimServicename/$($workspaceUrlPart)apis/$apiName/policies/policy"
    $qs = "?api-version=$restApiVersion"

    # NOTE: There may be an issue if you are creating the api... the api may not yet be provisioned when you try to apply the policy, resulting in an errir
    # Need to check the provisioning state to be sure... quick and dirty fix is to put a wait/sleep command here
    Start-Sleep -Seconds 2

    $null = Invoke-RestMethod -Method Put -Uri ($url + $qs) -Headers $headers -Body $body
}

function putApiOperationPolicyCreateUpdate{
    param(
        [string]$apiName,
        [string]$folderName,
        [string]$operationName
    )

    write-host "----------------------------Putting Operation Policy CreateUpdate for operation $operationName"

    $contents = Get-Content -Path "./$folderName/$operationName-policy.xml" -Raw

    $contents = $contents -replace "`r`n", ""

    $headers = @{
        'Authorization' = "Bearer $accessToken"
        'Content-Type' = 'application/json'
    }

    $body = "{""properties"": { ""format"": ""xml"", ""value"": ""$contents""}}"

    $url = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimServicename/$($workspaceUrlPart)apis/$apiName/operations/$operationName/policies/policy"
    $qs = "?api-version=$restApiVersion"

    $null = Invoke-RestMethod -Method Put -Uri ($url + $qs) -Headers $headers -Body $body
}

function removeApiFromList {
    param(
        [string]$apiFolder,
        [object]$apilist
    )

    write-host "----------------------------Removing API from list for folder $apiFolder"

    # Convert the JSON to a PowerShell object
    $jsonObject = @(Get-Content -Path "./api-list.json" -Raw | ConvertFrom-Json)

    # Remove the API from the object
    $jsonObject = $jsonObject | Where-Object { $_.'folder-name' -ne $apiFolder }

    # Convert the object back to JSON and overwrite the original file
    #$jsonObject | ConvertTo-Json -AsArray | Set-Content -Path "./api-list.json"

    $apilist = $jsonObject

    return $apilist
}

function addApiToList {
    param(
        [string]$apiFolder,
        [string]$apiName,
        [string]$apiPath,
        [object]$apilist
    )

    write-host "----------------------------Adding API to list for folder $apiFolder"

    # $apiName = getApiNameFromParams($apiFolder)
    ## Add the API to the api-list.json file

    # Convert the JSON to a PowerShell object
    #$jsonObject = @(Get-Content -Path "./api-list.json" -Raw | ConvertFrom-Json)
    $jsonObject = $apilist

    # Create a new object to add to the array
    $newApi = New-Object PSObject -Property @{
        'api-name' = $apiName
        'folder-name' = $apiFolder
        'api-path' = $apiPath
    }

    # Add the new object to the array
    $jsonObject += $newApi

    $apilist = $jsonObject

   return $apilist
}

function getApiInfoFromFile {
    param(
        [string]$apiFolder,
        [object]$apilist
    )

    write-host "----------------------------Getting API Info from file for folder $apiFolder"

    # Convert the JSON to a PowerShell object
    #$jsonObject = Get-Content -Path "./api-list.json" -Raw | ConvertFrom-Json
    $jsonObject = $apilist

    # Find the object with the matching folder-name
    $apiInfo= $jsonObject | Where-Object { $_.'folder-name' -eq $apiFolder }

    # Return the api-name
    return $apiInfo
}

function deleteApi {
    param(
        [string]$apiFolder,
        [object]$apilist
    )

    write-host "----------------------------Deleting API for folder $apiFolder"

    #Get API Info from api-list.json
    $apiInfo = getApiInfoFromFile -apiFolder $apiFolder -apilist $apilist
    $apiName = $apiInfo.'api-name'
    $apiFolder = $apiInfo.'folder-name'

    # Remove the API entry in api-list.json
    $apilist = removeApiFromList -apiFolder $apiFolder -apilist $apilist

    $headers = @{
        'Authorization' = "Bearer $accessToken"
    }

    $url = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimServiceName/$($workspaceUrlPart)apis/$apiName"
    $qs = "?api-version=$restApiVersion"

    $null = Invoke-RestMethod -Method Delete -Uri ($url + $qs) -Headers $headers

    return $apilist
}

function linkApiToProducts{
    param(
        [string]$apiName
    )

    write-host "----------------------------Linking API to Products for $apiName"

    $headers = @{
        'Authorization' = "Bearer $accessToken"
        'Content-Type' = 'application/json'
    }

    # Get a list of products (workspace or service level)
    $url = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimServicename/$($workspaceUrlPart)products"
    $qs = "?api-version=$restApiVersion"

    $null = Invoke-RestMethod -Method GET -Uri ($url + $qs) -Headers $headers

    # For each product, link it to the API
    foreach($product in $response.value) {
        Write-Output "----------------------------Linking api to product: $($product.name)"

        try{
            #Difference between workspace and service calls
            if ([string]::IsNullOrEmpty($workspaceName)) {
                # no workspaces used
                $url = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimServicename/products/$($product.name)/apis/$apiName"
                $qs = "?api-version=$restApiVersion"

                # Link the API to the product
                $null = Invoke-RestMethod -Method PUT -Uri ($url + $qs) -Headers $headers
            } else {
                # if using workspaces
                $body = "{""properties"": {""apiId"": ""/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimServicename/workspaces/$workspaceName/apis/$apiName""}}"
                $url = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimServicename/workspaces/$workspaceName/products/$($product.name)/apiLinks/$apiName$($product.name)"
                $qs = "?api-version=$restApiVersion"
                $null = Invoke-RestMethod -Method Put -Uri ($url + $qs) -Headers $headers -Body $body

            }

        }catch{
            Write-Host "Error linking api to product: $($product.name).  Link may have already existed."
        }
    }
}

function linkApiToTags{
    param(
        [string]$apiName
    )

    write-host "----------------------------Linking API to Tags for $apiName"

    $headers = @{
        'Authorization' = "Bearer $accessToken"
        'Content-Type' = 'application/json'
    }

    # Get a list of tags
    $url = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimServicename/$($workspaceUrlPart)tags"
    $qs = "?api-version=$restApiVersion"

    $null = Invoke-RestMethod -Method GET -Uri ($url + $qs) -Headers $headers

    foreach($tag in $response.value) {
        Write-Output "----------------------------Linking api to tag : $($tag.name)"

        try{
            # Difference between workspace and service calls
            if ([string]::IsNullOrEmpty($workspaceName)) {
                # no workspaces used
                $url = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimServicename/apis/$apiName/tags/$($tag.name)"
                $qs = "?api-version=$restApiVersion"

                # Link the API to the tag
                $null = Invoke-RestMethod -Method PUT -Uri ($url + $qs) -Headers $headers
            } else {
                # if using workspaces
                $body = "{""properties"": {""apiId"": ""/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimServicename/workspaces/$workspaceName/apis/$apiName""}}"
                $url = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimServicename/workspaces/$workspaceName/tags/$($tag.name)/apiLinks/$apiName$($tag.name)"
                $qs = "?api-version=$restApiVersion"
                $null = Invoke-RestMethod -Method Put -Uri ($url + $qs) -Headers $headers -Body $body
            }
        }catch{
            Write-Host "----------------------------Error linking api to tag: $($tag.name).  Link may have already existed."
        }
    }
}

function createApi {
    param (
        [string]$apiFolder,
        [object]$apilist
    )

    write-host "----------------------------Creating API for folder $apiFolder"

    # Scenario
    # API Folder Exists but API does not exist in api-list.json
    # Need to create the API in APIM and add it to the api-list.json file


    # Need to get the apiName and apiPath from the user for this API
    # This will cause an issue if you are getting apilist from a variable since we cannot prompt the user in a pipeline
    Write-Host "For the API in folder: $apiFolder"
    $apiName = Read-Host "Enter the API Name: "

    $apiPath = Read-Host "Enter the API Path: "

    # Add the API to the api-list.json file
    $apilist = addApiToList -apiFolder $apiFolder -apiName $apiName -apiPath $apiPath -apilist $apilist

    # Import the swagger to create the API
    # NOTE: Need to expand this to support other definition formats
    $null = putApiImportCreateUpdate -apiName $apiName -folderName $apiFolder -definitionFormat "swagger-json" -apiPath $apiPath 

    # Look for policy.xml if exists deploy it
    if ((Test-Path -Path "./$apiFolder/policy.xml")) {
        putApiPolicyCreateUpdate -apiName $apiName -folderName $apiFolder
    }

    # Look for <operation>-policy.xml if they exist, assume opperation name is correct and deploy them, outputting any errors
    $operationPolicyFiles = Get-ChildItem -Path ./$apiFolder -Filter "*-policy.xml"

    foreach ($operationPolicyFile in $operationPolicyFiles) {
        $operationName = [string]$operationPolicyFile.BaseName
        $operationName = $operationName.Replace("-policy", "")
        $null = putApiOperationPolicyCreateUpdate -apiName $apiName -folderName $apiFolder -operationName $operationName
    }

    # Associate API with products
    $null = linkApiToProducts -apiName $apiName

    # Associate API with tags
    $null = linkApiToTags -apiName $apiName

    return $apilist
}

function updateApi {
    param(
        [string]$apiFolder
    )

    write-host "----------------------------Updating API for folder $apiFolder"

    $apiInfo = getApiInfoFromFile -apiFolder $apiFolder -apilist $apilist
    $apiName = $apiInfo.'api-name'
    $folderName = $apiInfo.'folder-name'
    $apiPath = $apiInfo.'api-path'

    putApiImportCreateUpdate -apiName $apiName -folderName $folderName -definitionFormat "swagger-json" -apiPath $apiPath 
    

    # Does the policy.xml file exist
    #   Y: deploy it
    #   N: delete the policy on the API
    if ((Test-Path -Path "./$apiFolder/policy.xml")) {
        putApiPolicyCreateUpdate -apiName $apiName -folderName $apiFolder
    }else{
        $headers = @{
            'Authorization' = "Bearer $accessToken"
        }
    
        $apiName = $apiInfo.'api-name'
        $url = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimServiceName/$($workspaceUrlPart)apis/$apiName/policies/policy"
        $qs = "?api-version=$restApiVersion"
    
        $null = Invoke-RestMethod -Method Delete -Uri ($url + $qs) -Headers $headers
    }

    $operations = getApiOperations -apiName $apiInfo.'api-name'

    #   Does the <operation>-policy.xml file exist
    #       Y: deploy it
    #       N: delete the policy on the operation
    foreach($operation in $operations){
        if ((Test-Path -Path "./$apiFolder/$operation-policy.xml")) {
            putApiOperationPolicyCreateUpdate -apiName $apiName -folderName $apiFolder -operationName $operation
        }else{
            $headers = @{
                'Authorization' = "Bearer $accessToken"
            }
            $url = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimServiceName/$($workspaceUrlPart)apis/$apiName/operations/$operation/policies/policy"
            $qs = "?api-version=$restApiVersion"
        
            $null = Invoke-RestMethod -Method Delete -Uri ($url + $qs) -Headers $headers

        }
    }

    # Associate API with products
    $null = linkApiToProducts -apiName $apiName

    # Associate API with tags
    $null = linkApiToTags -apiName $apiName
}

function deployAPIs{
    param(
        [array]$apiListDirNames,
        [array]$filesysDirNames,
        [object]$apilist
    )

    write-host "----------------------------Deploying APIs"

    # Compare the list of APIs in the api-list.json file to the directories in the file system
    $differences = Compare-Object -ReferenceObject $apiListDirNames -DifferenceObject $filesysDirNames

    # For each difference, determine if an API needs to be created or deleted
    # Then remove it from the list of directories
    foreach ($difference in $differences) {
        if($difference.SideIndicator -eq "<=") {
            $apilist = deleteApi -apiFolder $difference.InputObject -apilist $apilist   #($difference.InputObject) # Delete the API
            $filesysDirNames = $filesysDirNames | Where-Object { $_ -ne $difference.InputObject } # Remove the API from the list
        }
        elseif($difference.SideIndicator -eq "=>") {
            $apilist = createApi -apiFolder  $difference.InputObject -apilist $apilist  #($difference.InputObject) # Create the API
            $filesysDirNames = $filesysDirNames | Where-Object { $_ -ne $difference.InputObject } # Remove the API from the list
        }
    }
    
    # Remaining directories are the ones that need to be updated
    foreach ($directory in $filesysDirNames) {
        updateApi -apiFolder $directory #($directory) # Update the API
    }

    return $apilist
}

function extractAPIs{
    param(
        [object]$apilist
    )

    write-host "----------------------------Extracting APIs"
    # Will extract APIs listed in api-list.json, must have the apiId correct and a folder name defined

    # Read the api-list.json file
    #$apiList = Get-Content -Path "./api-list.json" -Raw | ConvertFrom-Json
    $index=0
    foreach($api in $apiList){
        $apiName = $api.'api-name'
        $folderName = $api.'folder-name'
        
        # If API folder doesn't exist, create it
        # If it does exist, delete everything within it
        if (!(Test-Path -Path "./$folderName")) {
            New-Item -Path "./$folderName" -ItemType Directory -Force
        }else {
            Remove-Item -Path "./$folderName/*" -Recurse -Force
        }

        # Extract the definition file into the folder
        $apiPath = getApiExport -apiName $apiName -definitionFormat "swagger-json" -folderName $folderName 

        # Update the path statement in apiList make sure to remove the leading / from the path
        if ([string]::IsNullOrEmpty($apiPath)) {
            $apiList[$index].'api-path' = ""
        } else {
            $apiList[$index].'api-path' = $apiPath.TrimStart('/')
        }
        
        # Extract the api Policy file into the folder
        getApiPolicy -apiName $apiName -folderName $folderName 

        # Extract the operation policy files into the folder
        getOperationPolicys -apiName $apiName -folderName $folderName 
        $index++

        # Associate API with products - dev may not have done this when doing portal first development
        linkApiToProducts -apiName $apiName

        # Associate API with tags - dev may not have done this when doing portal first development
        linkApiToTags -apiName $apiName
    }

    # Update the path statements in the api-list.json file
    #$apiList | ConvertTo-Json -AsArray | Set-Content -Path "./api-list.json"
    return $apiList
}

Write-Host "-----------------------------------------------------------"
Write-Host "| NOTE: This script is POC quality, not production ready. |"
Write-Host "|      There is no error handling or validation.          |"
Write-Host "-----------------------------------------------------------"
Write-Host
Write-Host "Working directory: $workingDirectory"
Write-Host "Script directory: $PSScriptRoot"

# Get the access token
$context = Get-AzContext
$profile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
$profileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient -ArgumentList ($profile)
$token = $profileClient.AcquireAccessToken($context.Subscription.TenantId)
$accessToken = $token.AccessToken

if ($apilistjsonparam -eq $null -or $apilistjsonparam -eq "") {
    Write-Host "----------------------------Using api-list.json file"
    # Script to Deploy APIs, maintain the api-list.json file, and delete APIs that are no longer needed.
    # Check if api-list.json exists, if not, create it and seed it with an empty json array
    if (!(Test-Path -Path "./api-list.json")) {
        New-Item -ItemType File -Path "./api-list.json" -Force
        Set-Content -Path "./api-list.json" -Value '[]'
    }

    $apilist = @(Get-Content -Path "./api-list.json" -Raw | ConvertFrom-Json)
} else {
    Write-Host "----------------------------Using apilistjsonparam"
    $apilist = @($apilistjsonparam | ConvertFrom-Json)
}

$apiListDirNames = @()
foreach ($api in $apilist) {
    $apiListDirNames += $api.'folder-name'
}

if ([string]::IsNullOrEmpty($workspaceName)) {
    $workspaceUrlPart = ""
} else {
    $workspaceUrlPart = "workspaces/$workspaceName/"
}

# Get all the directory names in the current directory
$filesysDirNames= (Get-ChildItem -Path "." -Directory).name

if($scriptFunction -eq "Deploy"){
    $apilist = deployAPIs -apiListDirNames $apiListDirNames -filesysDirNames $filesysDirNames -apilist $apilist

}elseif($scriptFunction -eq "Extract"){
    $apilist = extractAPIs -apilist $apilist
    
} else {
    Write-Host "----------------------------Invalid script function"
}

Write-Host "----------------------------Updating api-list.json"
$apilist | ConvertTo-Json -AsArray | Set-Content -Path "./api-list.json"

