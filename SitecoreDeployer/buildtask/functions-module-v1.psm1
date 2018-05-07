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

#this function is called to limit access to processing instance, if it is found
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

    $prcInstanceName = Get-VstsInput -Name prcInstanceName;
    if ([string]::IsNullOrWhiteSpace($prcInstanceName))
    {
        Write-Host "##vso[task.logissue type=warning;] LimitAccessToPrc: PRC web app name is not set, falling back to default resource group name + '-prc'"
        $prcInstanceName = $rgName + "-prc/prc-staging"
    }

    Write-Verbose "PRC instance name is $prcInstanceName"

    #get list of IP, defined by user
    $prcIpList = Get-VstsInput -Name prcIpMaskCollection;

    SetWebAppRestrictions -userInputIpList $prcIpList -webAppInstanceName $prcInstanceName -resourceGroupName $rgName
}

function SetWebAppRestrictions {
    param (
        $userInputIpList,
        $webAppInstanceName,
        $resourceGroupName
    )
    $IpSecurityRestrictions = GenerateIpMaskHashTableFromUserInput -ipMaskUserInputString $userInputIpList

    #get API version to work with Azure Web apps
    $APIVersion = ((Get-AzureRmResourceProvider -ProviderNamespace Microsoft.Web).ResourceTypes | Where-Object ResourceTypeName -eq sites).ApiVersions[0];
    #by default, we are supposing we are working with slots
    $isSlot = $false
    #if instance name does not contain / - it is not a slot :)
    if ($webAppInstanceName.contains('/')) {
        $isSlot = $true
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

    $WebAppConfig.Properties.ipSecurityRestrictions = $IpSecurityRestrictions;
    $WebAppConfig | Set-AzureRmResource -ApiVersion $APIVersion -Force | Out-Null
}

function GenerateIpMaskHashTableFromUserInput {
    param ( $ipMaskUserInputString )

    $restrictionsHashtable = @()
    #localhost shall be allowed by default :)
    $webIP = [PSCustomObject]@{ipAddress = ''; subnetMask = ''}
    $webIP.ipAddress = '127.0.0.1'
    $webIP.subnetMask = '255.255.255.255'
    $restrictionsHashtable.Add($webIP) | Out-Null

    if ([string]::IsNullOrWhiteSpace($ipMaskUserInputString)) {
        Write-Host "##vso[task.logissue type=warning;] LimitAccessToPrc: IP List is not defined by user"
    }
    else {
        Write-Host "##vso[task.logissue type=warning;] LimitAccessToPrc: Adding user defined IP list"
        #split on comma
        foreach ($inputIpMask in $ipMaskUserInputString.Split(',')) {
            $ipAddr = ($inputIpMask.Split('/'))[0].ToString
            $mask = ($inputIpMask.Split('/'))[1].ToString
            if (-not ($ipAddr -in $restrictionsHashtable.ipAddress)) {
                $ipHash = [PSCustomObject]@{ipAddress=''; subnetMask = ''}
                $ipHash.ipAddress = $ipAddr
                $ipHash.subnetMask = $mask
                Write-Verbose "Adding following IP to restrictions:"
                Write-Verbose $ipHash
                $restrictionsHashtable.Add($ipHash) | Out-Null
            }
        }
    }
    #Display content for debug reasons
    Write-Verbose "These IP restrictions will be set"
    Write-Verbose $restrictionsHashtable;
    return $restrictionsHashtable;
}
