function ConvertPSObjectToHashtable
{
    param (
        [Parameter(ValueFromPipeline)]
        $InputObject
    )

    process
    {
        if ($null -eq $InputObject) { return $null }

        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string])
        {
            $collection = @(
                foreach ($object in $InputObject) { ConvertPSObjectToHashtable $object }
            )

            Write-Output -NoEnumerate $collection
        }
        elseif ($InputObject -is [psobject])
        {
            $hash = @{}

            foreach ($property in $InputObject.PSObject.Properties)
            {
                $hash[$property.Name] = ConvertPSObjectToHashtable $property.Value
            }

            $hash
        }
        else
        {
            $InputObject
        }
    }
}

$global:blobBaseDomain = ".blob.core.windows.net"
$global:generatedSas = New-Object -TypeName Hashtable;
function TryGenerateSas {
    param (
        $maybeStorageUri
    )

    process {
        Write-Verbose "Starting TryGenerateSas"

        if ($maybeStorageUri -match '%') {
            Write-Verbose "TryGenerateSas: $maybeStorageUri already escaped"
            #percent sign is not allowed in URL by itself, so, if it is present - this URI is escaped already
            $escapedUri = $maybeStorageUri
        } else {
            Write-Verbose "TryGenerateSas: $maybeStorageUri not escaped"
            $escapedUri = [uri]::EscapeUriString($maybeStorageUri)
            Write-Verbose "TryGenerateSas: $maybeStorageUri have been escaped to $escapedUri"
        }

        if ([string]::IsNullOrEmpty($escapedUri)) {
            Write-Host "##vso[task.logissue type=warning;] TryGenerateSas: URL is empty"
            return $escapedUri
        }
        if (-Not [system.uri]::IsWellFormedUriString($escapedUri,[System.UriKind]::Absolute)) {
            #check, if it actually absolute URI
            Write-Host "##vso[task.logissue type=warning;] TryGenerateSas: URL $escapedUri is not absolute"
            return $escapedUri
        }
        if ($escapedUri -inotmatch "$blobBaseDomain") {
            Write-Host "##vso[task.logissue type=warning;] TryGenerateSas: URL $escapedUri does not contain $blobBaseDomain"
            #InputUri does not contains blob.core.windows.net
            return $escapedUri
        }
        $parsedUri = [Uri]$escapedUri
        $storageAccountName = $parsedUri.DnsSafeHost -replace "$blobBaseDomain", ""
        if ([string]::IsNullOrEmpty($storageAccountName)) {
            Write-Host "##vso[task.logissue type=warning;] TryGenerateSas: Could not retrieve storage account from $escapedUri"
            return $escapedUri
        }

        $containerName = $parsedUri.Segments[1]
        if ([string]::IsNullOrEmpty($containerName)) {
            Write-Host "##vso[task.logissue type=warning;] TryGenerateSas: Could not retrieve container name from $escapedUri"
            return $escapedUri
        }
        $containerName = $containerName -replace '/',""
        if ([string]::IsNullOrEmpty($containerName)) {
            Write-Host "##vso[task.logissue type=warning;] TryGenerateSas: Container name from $escapedUri is empty"
            return $escapedUri
        }

        $sasKey = $storageAccountName + "-" + $containerName
        $packageUri = $escapedUri
        if ($generatedSas.ContainsKey($sasKey)) {
            #we already generated SAS for this container
            if (-not [string]::IsNullOrEmpty($generatedSas[$sasKey])) {
                $packageUri = $parsedUri.Scheme + "://" + $parsedUri.DnsSafeHost + $parsedUri.LocalPath + $generatedSas[$sasKey]
            }
        }
        else {
            #we need to generate a SAS
            $sasValue = GenerateSasForStorageURI -storageAccountName $storageAccountName -containerName $containerName;
            #if $sasValue is not empty - we shall implement it
            if (-not [string]::IsNullOrEmpty($sasValue)) {
                #store generated SAS in global variable, as getting storage is time consuming process
                $generatedSas.Add($sasKey, $sasValue)
                $packageUri = $parsedUri.Scheme + "://" + $parsedUri.DnsSafeHost + $parsedUri.LocalPath + $sasValue
            }
        }
        Write-Verbose "Ended TryGenerateSas"
        return  $packageUri
    }
}

function GenerateSasForStorageURI {
    param (
        $storageAccountName,
        $containerName
    )

    process {
        Write-Verbose "Starting GenerateSasForStorageURI"
        #Processes input string and, if it storage URI - tries to generate a short living (10 hours) SAS for it

        $storageAccount = Get-AzureRmStorageAccount | Where-Object {$_.StorageAccountName -eq $storageAccountName}
        if ($null -eq $storageAccount) {
            Write-Host "##vso[task.logissue type=warning;] GenerateSasForStorageURI: Could not get storage $storageAccountName"
            #could not get storage account :(
            return ""
        }

        $now = [System.DateTime]::Now
        #construct SAS token for a container
        $SAStokenQuery = New-AzureStorageContainerSASToken -Name $containerName -Context $storageAccount.Context -Permission r -StartTime $now.AddHours(-1) -ExpiryTime $now.AddHours(10)
        Write-Verbose "Ended GenerateSasForStorageURI"
        return $SAStokenQuery
    }
}

function CheckIfPossiblyUriAndIfNeedToGenerateSas {
    param (
        $name,
        $generate
    )

    process {
        Write-Debug $generate
        if ($generate)
        {
            if ($name -imatch "msdeploy" -or $name -imatch "url") {
                return $true
            }
            else {
                return $false
            }
        }
        return $false
    }
}

function CollectOutBoundIpAddresses {
    param ($resourceGroupName)

    $collectedIps = "";
    #Get all resources, which are in resource groups, which contains our name
    $resources = Get-AzureRmResource -ResourceGroupName $resourceGroupName
    $resourcesAmount = ($resources | Measure-Object).Count
    if ($resourcesAmount -le 0) {
        Write-Host "##vso[task.logissue type=warning;] CollectOutBoundIpAddresses: Could not retrieve any resources in given resource group"
        return $collectedIps;
    }
    $webApps = $resources.where( {$_.ResourceType -eq "Microsoft.Web/sites" -And $_.ResourceGroupName -eq "$ResourceGroupName"})
    $webAppsAmount = ($webApps | Measure-Object).Count
    if ($webAppsAmount -le 0) {
        Write-Host "##vso[task.logissue type=warning;] CollectOutBoundIpAddresses: Could not retrieve any web apps in given resource group"
        return $collectedIps;
    }

    foreach ($webApp in $webApps) {
        $collectedIps += CollectWebAppOutboundIpAddresses -resourceGroupName $ResourceGroupName -webAppName $webApp.Name -resourcePresenceChecked $true
    }
    return $collectedIps.TrimEnd(',');
}

#get outbound IP addresses for 1 web app
function CollectWebAppOutboundIpAddresses{
    param (
        $resourceGroupName,
        $webAppName,
        #flag to check presence of resource in Azure
        $resourcePresenceChecked = $false
        )

    $webAppOutboundIPs = ""
    #$APIVersion = ((Get-AzureRmResourceProvider -ProviderNamespace Microsoft.Web).ResourceTypes | Where-Object ResourceTypeName -eq sites).ApiVersions[0];
    $APIVersion = "2018-02-01"

    if (!$resourcePresenceChecked) {
        #get all resrouces in current resource group, and check if resource is present there
        $webAppResource = (Get-AzureRmResource -ResourceGroupName $resourceGroupName).where({$_.Name -eq "$webAppName" -And $_.ResourceGroupName -eq "$resourceGroupName"})
        #measure found amount and if less or equal to 0 - we could not find web app
        if (($webAppResource | Measure-Object).Count -le 0) {
            Write-Host "##vso[task.logissue type=warning;] CollectWebAppOutboundIpAddresses: Could not find web app $webAppName in resource group $resourceGroupName. Returning back"
            return;
        }
    }

    $WebAppConfig = (Get-AzureRmResource -ResourceType Microsoft.Web/sites -ResourceName $webAppName -ResourceGroupName $resourceGroupName -ApiVersion $APIVersion)
    foreach ($ip in $WebAppConfig.Properties.outboundIpAddresses.Split(',')) {
        $valueToAdd = $ip + "/255.255.255.255,";
        $webAppOutboundIPs += $valueToAdd;
    }
    return $webAppOutboundIPs;
}

function SetWebAppRestrictions {
    param (
        $userInputIpList,
        $webAppInstanceName,
        $resourceGroupName
    )
    $restrictionsHashtable = @()
    #localhost shall be allowed by default :)
    $webIP = [PSCustomObject]@{ipAddress = ''; subnetMask = ''}
    $webIP.ipAddress = '127.0.0.1'
    $webIP.subnetMask = '255.255.255.255'
    Write-Verbose "Adding following IP to restrictions:"
    Write-Verbose $webIP
    $restrictionsHashtable += $webIP

    if ([string]::IsNullOrWhiteSpace($userInputIpList)) {
        Write-Host "##vso[task.logissue type=warning;] SetWebAppRestrictions: IP List is not defined by user"
    }
    else {
        Write-Host "##vso[task.logissue type=warning;] SetWebAppRestrictions: Defining IP list (defined by user + collected outbound IP for $webAppInstanceName instance)"
        #split on comma
        foreach ($inputIpMask in $userInputIpList.Split(',',[System.StringSplitOptions]::RemoveEmptyEntries)) {
            $ipAddr = ($inputIpMask.Split('/'))[0].ToString().Trim()
            $mask = ($inputIpMask.Split('/'))[1].ToString().Trim()
            if (-not ($ipAddr -in $restrictionsHashtable.ipAddress)) {
                $ipHash = [PSCustomObject]@{ipAddress=''; subnetMask = ''}
                $ipHash.ipAddress = $ipAddr
                $ipHash.subnetMask = $mask
                Write-Verbose "Adding following IP to restrictions:"
                Write-Verbose $ipHash
                $restrictionsHashtable += $ipHash
            }
        }
    }

    #get API version to work with Azure Web apps
    #$APIVersion = ((Get-AzureRmResourceProvider -ProviderNamespace Microsoft.Web).ResourceTypes | Where-Object ResourceTypeName -eq sites).ApiVersions[0];
    #in latest APIVerions (2018-02-01) - something changed on setting web app IP restrictions, so, I will use the last, where this code executes OK
    $APIVersion = "2016-08-01";
    #by default, we are supposing we are working with slots
    $isSlot = $false
    #if instance name does not contain / - it is not a slot :)
    if ($webAppInstanceName.contains('/')) {
        $isSlot = $true
    }

    #get all resrouces in current resource group, and check if resource is present there
    $webAppResource = (Get-AzureRmResource -ResourceGroupName $resourceGroupName).where({$_.Name -eq "$webAppInstanceName" -And $_.ResourceGroupName -eq "$ResourceGroupName"})
    #measure found amount and if less or equal to 0 - we could not find web app
    if (($webAppResource | Measure-Object).Count -le 0) {
        Write-Host "##vso[task.logissue type=warning;] SetWebAppRestrictions: Could not find web app $webAppInstanceName in resource group $ResourceGroupName. Returning back"
        return;
    }
    #get current web app config
    if ($isSlot) {
        Write-Verbose "We are working with slot"
        $WebAppConfig = (Get-AzureRmResource -ResourceType Microsoft.Web/sites/slots/config -ResourceName $webAppInstanceName -ResourceGroupName $resourceGroupName -ApiVersion $APIVersion)
    } else {
        Write-Verbose "We are working with web app"
        $WebAppConfig = (Get-AzureRmResource -ResourceType Microsoft.Web/sites/config -ResourceName $webAppInstanceName -ResourceGroupName $resourceGroupName -ApiVersion $APIVersion)
    }

    Write-Verbose "Web app configuration received:"
    Write-Verbose $WebAppConfig

    $WebAppConfig.Properties.ipSecurityRestrictions = $restrictionsHashtable;
    $WebAppConfig | Set-AzureRmResource -ApiVersion $APIVersion -Force | Out-Null
}

function GenerateInstanceName {
    param (
        $rgName,
        $roleName
    )

    $generatedInstanceName = $rgName + "-" + $roleName + "/" + $roleName + "-staging";
    Write-Verbose "GenerateInstanceName: instance name for role $roleName is $generatedInstanceName"
    return $generatedInstanceName
}

function LimitAccessToInstance {
    param (
        $rgName,
        $instanceName,
        $instanceRole,
        $limitAccessToInstanceAsString,
        $ipMaskCollectionUserInput
    )

    $instanceRole = $instanceRole.ToLower();
    #convert it to Boolean
    $LimitInstanceAccess = [System.Convert]::ToBoolean($limitAccessToInstanceAsString)
    if (!$LimitInstanceAccess) {
        Write-Host "##vso[task.logissue type=warning;] LimitAccessToInstance: Access to $instanceRole role shall not be limited by task"
        return;
    }

    if ([string]::IsNullOrWhiteSpace($instanceName))
    {
        $instanceName = GenerateInstanceName -rgName $rgName -roleName $instanceRole
        Write-Host "##vso[task.logissue type=warning;] LimitAccessToInstance: $instanceRole web app name is not set, falling back to default resource group name + '-roleName/roleName-staging' - $instanceName"
    }

    Write-Verbose "$instanceRole instance name is $instanceName"

    Write-Verbose "Defined by user ip collection is $ipMaskCollectionUserInput"
    #if provided reporting IP list is not emptry and not ends with comma - we shall add comma to the end  here
    if (![string]::IsNullOrWhiteSpace($ipMaskCollectionUserInput)) {
        if ($ipMaskCollectionUserInput -notmatch '.+?,$') {
            $ipMaskCollectionUserInput += ','
        }
    }
    #reporting instance shall be accessible by all other instances as well
    if ($instanceRole -eq "rep" -Or $instanceRole -eq "cm") {
        Write-Verbose "Collecting outbound IPs for $instanceRole role"
        #collect outbount IP addresses
        $collectedOutBoundIps = CollectOutBoundIpAddresses -resourceGroupName $rgName
        if (![string]::IsNullOrWhiteSpace($collectedOutBoundIps)) {
            #add outbound IPs to provided by user input if any
            $ipMaskCollectionUserInput += $collectedOutBoundIps
        }
    }

    #processing shall be able to reach itself on outbount IPs
    if ($instanceRole -eq "prc") {
        Write-Verbose "Collecting outbound IPs for $instanceRole role"
        $collectedOutBoundIps = CollectWebAppOutboundIpAddresses -resourceGroupName $rgName -webAppName $instanceName
        if (![string]::IsNullOrWhiteSpace($collectedOutBoundIps)) {
            #add outbound IPs to provided by user input if any
            $ipMaskCollectionUserInput += $collectedOutBoundIps
        }
    }

    Write-Verbose "We are going to write this IP restrictions to $instanceRole web app: $ipMaskCollectionUserInput"

    SetWebAppRestrictions -userInputIpList $ipMaskCollectionUserInput -webAppInstanceName $instanceName -resourceGroupName $rgName
}

function ListArmParameters {
    param (
        $inputMessage,
        $armParamatersHashTable
    )

    Write-Verbose "ListArmParameters: $inputMessage"
    foreach($key in $armParamatersHashTable.keys)
    {
        $message = '{0} is {1}' -f $key, $armParamatersHashTable[$key]
        Write-Verbose $message
    }
    Write-Verbose "ListArmParameters: ended"
}