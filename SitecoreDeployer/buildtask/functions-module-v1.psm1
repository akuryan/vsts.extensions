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
        $escapedUri = [uri]::EscapeUriString($maybeStorageUri)

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
    $resources = Find-AzureRmResource -ResourceGroupNameContains $resourceGroupName
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

    $APIVersion = ((Get-AzureRmResourceProvider -ProviderNamespace Microsoft.Web).ResourceTypes | Where-Object ResourceTypeName -eq sites).ApiVersions[0];
    foreach ($webApp in $webApps) {
        $WebAppConfig = (Get-AzureRmResource -ResourceType Microsoft.Web/sites -ResourceName $webApp.Name -ResourceGroupName $ResourceGroupName -ApiVersion $APIVersion)
        foreach ($ip in $WebAppConfig.Properties.outboundIpAddresses.Split(',')) {
            $valueToAdd = $ip + "/255.255.255.255,";
            $collectedIps += $valueToAdd;
        }
    }
    return $collectedIps.TrimEnd(',');
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
        Write-Host "##vso[task.logissue type=warning;] SetWebAppRestrictions: Adding user defined IP list"
        #split on comma
        foreach ($inputIpMask in $userInputIpList.Split(',')) {
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
    $APIVersion = ((Get-AzureRmResourceProvider -ProviderNamespace Microsoft.Web).ResourceTypes | Where-Object ResourceTypeName -eq sites).ApiVersions[0];
    #by default, we are supposing we are working with slots
    $isSlot = $false
    #if instance name does not contain / - it is not a slot :)
    if ($webAppInstanceName.contains('/')) {
        $isSlot = $true
    }

    #get all resrouces in current resource group, and check if resource is present there
    $webAppResource = (Find-AzureRmResource -ResourceGroupNameContains $resourceGroupName).where({$_.Name -eq "$webAppInstanceName" -And $_.ResourceGroupName -eq "$ResourceGroupName"})
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

function LimitAccessToPrc {
    param (
        $rgName
    )
    #get input
    $limitPrcAccessInput = Get-VstsInput -Name limitAccesToPrc -Require
    #convert it to Boolean
    $LimitPrcAccess = [System.Convert]::ToBoolean($limitPrcAccessInput)
    if (!$LimitPrcAccess) {
        Write-Host "##vso[task.logissue type=warning;] LimitAccessToPrc: Access to PRC shall not be limited by task"
        return;
    }

    $instanceNamePrc = Get-VstsInput -Name prcInstanceName;
    if ([string]::IsNullOrWhiteSpace($instanceNamePrc))
    {
        Write-Host "##vso[task.logissue type=warning;] LimitAccessToPrc: PRC web app name is not set, falling back to default resource group name + '-prc/prc-staging'"
        $instanceNamePrc = $rgName + "-prc/prc-staging"
    }

    Write-Verbose "PRC instance name is $instanceNamePrc"

    #get list of IP, defined by user
    $prcIpList = Get-VstsInput -Name ipMaskCollection;
    Write-Verbose "We are going to write this IP restrictions to PRC web app: $prcIpList"

    SetWebAppRestrictions -userInputIpList $prcIpList -webAppInstanceName $instanceNamePrc -resourceGroupName $rgName
}

function LimitAccessToRep {
    param (
        $rgName
    )
    #get input
    $limitRepAccessInput = Get-VstsInput -Name limitAccesToRep -Require
    #convert it to Boolean
    $LimitPrcAccess = [System.Convert]::ToBoolean($limitRepAccessInput)
    if (!$LimitPrcAccess) {
        Write-Host "##vso[task.logissue type=warning;] LimitAccessToRep: Access to REP shall not be limited by task"
        return;
    }

    $instanceNameRep = Get-VstsInput -Name repInstanceName;
    if ([string]::IsNullOrWhiteSpace($instanceNameRep))
    {
        Write-Host "##vso[task.logissue type=warning;] LimitAccessToRep: REP web app name is not set, falling back to default resource group name + '-rep/rep-staging'"
        $instanceNameRep = $rgName + "-rep/rep-staging"
    }

    Write-Verbose "REP instance name is $instanceNameRep"

    #get list of IP, defined by user
    $repIpList = Get-VstsInput -Name ipMaskCollection;
    Write-Verbose "Defined by user ip collection is $repIpList"
    #collect outbount IP addresses
    $collectedOutBoundIps = CollectOutBoundIpAddresses -resourceGroupName $rgName
    if (![string]::IsNullOrWhiteSpace($collectedOutBoundIps)) {
        #if provided reporting IP list is not emptry and not ends with comma - we shall add comma to the end  here
        if (![string]::IsNullOrWhiteSpace($repIpList)) {
            if ($repIpList -notmatch '.+?,$') {
                $repIpList += ','
            }
        }
        #add outbound IPs to provided by user input if any
        $repIpList += $collectedOutBoundIps
    }

    Write-Verbose "We are going to write this IP restrictions to REP web app: $repIpList"

    SetWebAppRestrictions -userInputIpList $repIpList -webAppInstanceName $instanceNameRep -resourceGroupName $rgName
}
