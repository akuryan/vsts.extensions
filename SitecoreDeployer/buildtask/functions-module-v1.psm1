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
        Write-Verbose "Starting TryGenerateSas";

        if ($maybeStorageUri -match '%') {
            Write-Verbose "TryGenerateSas: $maybeStorageUri already escaped";
            #percent sign is not allowed in URL by itself, so, if it is present - this URI is escaped already
            $escapedUri = $maybeStorageUri;
        } else {
            Write-Verbose "TryGenerateSas: $maybeStorageUri not escaped";
            $escapedUri = [uri]::EscapeUriString($maybeStorageUri);
            Write-Verbose "TryGenerateSas: $maybeStorageUri have been escaped to $escapedUri";
        }

        if ([string]::IsNullOrEmpty($escapedUri)) {
            Write-Host "##vso[task.logissue type=warning;] TryGenerateSas: URL is empty";
            return $escapedUri;
        }
        if (-Not [system.uri]::IsWellFormedUriString($escapedUri,[System.UriKind]::Absolute)) {
            #check, if it actually absolute URI
            Write-Host "##vso[task.logissue type=warning;] TryGenerateSas: URL $escapedUri is not absolute";
            return $escapedUri;
        }
        if ($escapedUri -inotmatch "$blobBaseDomain") {
            Write-Host "##vso[task.logissue type=warning;] TryGenerateSas: URL $escapedUri does not contain $blobBaseDomain";
            #InputUri does not contains blob.core.windows.net
            return $escapedUri;
        }  

        $parsedUri = [Uri]$escapedUri;
        $storageAccountName = $parsedUri.DnsSafeHost -replace "$blobBaseDomain", "";
        if ([string]::IsNullOrEmpty($storageAccountName)) {
            Write-Host "##vso[task.logissue type=warning;] TryGenerateSas: Could not retrieve storage account from $escapedUri";
            return $escapedUri;
        }

        $containerName = $parsedUri.Segments[1];
        if ([string]::IsNullOrEmpty($containerName)) {
            Write-Host "##vso[task.logissue type=warning;] TryGenerateSas: Could not retrieve container name from $escapedUri";
            return $escapedUri;
        }
        $containerName = $containerName -replace '/',"";
        if ([string]::IsNullOrEmpty($containerName)) {
            Write-Host "##vso[task.logissue type=warning;] TryGenerateSas: Container name from $escapedUri is empty";
            return $escapedUri;
        }

        $sasKey = $storageAccountName + "-" + $containerName;
        $packageUri = $escapedUri;
        if ($generatedSas.ContainsKey($sasKey)) {
            #we already generated SAS for this container
            if (-not [string]::IsNullOrEmpty($generatedSas[$sasKey])) {
                $packageUri = $parsedUri.Scheme + "://" + $parsedUri.DnsSafeHost + $parsedUri.LocalPath + $generatedSas[$sasKey];
            }
        }
        else {
            #we need to generate a SAS
            $sasValue = GenerateSasForStorageURI -storageAccountName $storageAccountName -containerName $containerName;
            #if $sasValue is not empty - we shall implement it
            if (-not [string]::IsNullOrEmpty($sasValue)) {
                #store generated SAS in global variable, as getting storage is time consuming process
                $generatedSas.Add($sasKey, $sasValue);
                $packageUri = $parsedUri.Scheme + "://" + $parsedUri.DnsSafeHost + $parsedUri.LocalPath + $sasValue;
            }
        }
        Write-Verbose "Ended TryGenerateSas";
        return  $packageUri;
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

function RetrieveAllWebApps {
    param (
        [string]$rgName,
        [string]$resType = "Microsoft.Web/sites"
    )
    
    #Get all resources, which are in resource groups, which contains our name
    $resources = Get-AzureRmResource -ODataQuery "`$filter=resourcegroup eq '$rgName'";
    $resourcesAmount = ($resources | Measure-Object).Count;
    if ($resourcesAmount -le 0) {
        Write-Host "##vso[task.logissue type=warning;] RetrieveAllWebApps: Could not retrieve any resources in given resource group";
        return;
    }
    return $resources.where( {$_.ResourceType -eq $resType -And $_.ResourceGroupName -eq "$rgName"});
}

function CollectOutBoundIpAddresses {
    param ($resourceGroupName)

    $collectedIps = "";
    $webApps = RetrieveAllWebApps -rgName $resourceGroupName;
    $webAppsAmount = ($webApps | Measure-Object).Count;
    if ($webAppsAmount -le 0) {
        Write-Host "##vso[task.logissue type=warning;] CollectOutBoundIpAddresses: Could not retrieve any web apps in given resource group";
        return $collectedIps;
    }

    foreach ($webApp in $webApps) {
        $collectedIps += CollectWebAppOutboundIpAddresses -resourceGroupName $ResourceGroupName -webAppName $webApp.Name -resourcePresenceChecked $true;
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

    $webAppOutboundIPs = "";
    $APIVersion = GetWebAppApiVersion;

    if (!$resourcePresenceChecked) {
        #get all resrouces in current resource group, and check if resource is present there
        $webAppResource = (Get-AzureRmResource).where({$_.Name -eq "$webAppName" -And $_.ResourceGroupName -eq "$resourceGroupName"})
        #measure found amount and if less or equal to 0 - we could not find web app
        if (($webAppResource | Measure-Object).Count -le 0) {
            Write-Host "##vso[task.logissue type=warning;] CollectWebAppOutboundIpAddresses: Could not find web app $webAppName in resource group $resourceGroupName. Returning back"
            return;
        }
    }

    $WebAppConfig = (Get-AzureRmResource -ResourceType Microsoft.Web/sites -ResourceName $webAppName -ResourceGroupName $resourceGroupName -ApiVersion $APIVersion)
    foreach ($ip in $WebAppConfig.Properties.outboundIpAddresses.Split(',')) {
        $valueToAdd = $ip + "/32,";
        $webAppOutboundIPs += $valueToAdd;
    }
    return $webAppOutboundIPs;
}

function GetWebAppApiVersion {
    #get API version to work with Azure Web apps
    #$apiV = ((Get-AzureRmResourceProvider -ProviderNamespace Microsoft.Web).ResourceTypes | Where-Object ResourceTypeName -eq sites).ApiVersions[0];
    $apiV = "2018-02-01";
    Write-Verbose "API version for web apps is $apiV";
    return $apiV;
}

function SplitIpStringToHashTable {
    param (
        [string]$ipCollectionString
    )

    $returnHashtable = @();

    $counter = 100;

    #split on comma
    foreach ($inputIpMask in $ipCollectionString.Split(',',[System.StringSplitOptions]::RemoveEmptyEntries)) {
        if ($inputIpMask.Contains('/')) {
            $ipAddr = ($inputIpMask.Split('/'))[0].ToString().Trim();
            $mask = ($inputIpMask.Split('/'))[1].ToString().Trim();
        } else {
            $ipAddr = $inputIpMask;
            $mask = "32";
        }

        #convert mask to CIDR
        if ($mask.Length -gt 2) {
            #this is regular network mask and it must be converted;
            $result = 0;
            try {
                #ensure that we have valid IP address in our mask specified
                [IPAddress]$ip = $mask;
                $octets = $ip.IPAddressToString.Split('.');
                foreach($octet in $octets)
                {
                  while(0 -ne $octet) 
                  {
                    $octet = ($octet -shl 1) -band [byte]::MaxValue;
                    $result++; 
                  }
                }
                [string]$mask = $result;
            }
            catch {
                Write-Host "##vso[task.logissue type=warning;] Could not transform mask $mask from $inputIpMask to CIDR";
                continue;
            }
        }

        #form CIDR notation
        $ipAddr = $ipAddr + "/" + $mask;

        if (-not ($ipAddr -in $returnHashtable.ipAddress)) {
            $ipHash = [PSCustomObject]@{ipAddress = $ipAddr; action = "Allow"; priority = $counter; name = "Allow $ipAddr"; description = "Added by Sitecore Deployer"};
            Write-Verbose "Adding following IP to restrictions: $ipAddr";
            Write-Verbose $ipHash;
            $returnHashtable += $ipHash;
            $counter++;
        } else {
            Write-Host "Same IP $ipAddr detected in collection $ipCollectionString and it is not added";
        }
    }
    return $returnHashtable;
}

function SetWebAppRestrictions {
    param (
        $ipList,
        $webAppInstanceName,
        $resourceGroupName
    )
    $restrictionsHashtable = @();
    #localhost shall be allowed by default :)
    $ipList = $ipList + ",127.0.0.1/32,127.0.0.2/32";

    if ([string]::IsNullOrWhiteSpace($ipList)) {
        Write-Host "##vso[task.logissue type=warning;] SetWebAppRestrictions: IP List is not defined";
    }
    else {
        Write-Host "##vso[task.logissue type=warning;] SetWebAppRestrictions: Defining IP list (defined by user + collected outbound IP for $webAppInstanceName instance)";
        $restrictionsHashtable += SplitIpStringToHashTable -ipCollectionString $ipList;
    }

    $APIVersion = GetWebAppApiVersion;
    #by default, we are supposing we are working with slots
    $isSlot = $false;
    #if instance name does not contain / - it is not a slot :)
    if ($webAppInstanceName.contains('/')) {
        $isSlot = $true;
    }

    #get all resrouces in current resource group, and check if resource is present there
    $webAppResource = (Get-AzureRmResource).where({$_.Name -eq "$webAppInstanceName" -And $_.ResourceGroupName -eq "$ResourceGroupName"});
    #measure found amount and if less or equal to 0 - we could not find web app
    if (($webAppResource | Measure-Object).Count -le 0) {
        Write-Host "##vso[task.logissue type=warning;] SetWebAppRestrictions: Could not find web app $webAppInstanceName in resource group $ResourceGroupName. Returning back";
        return;
    }
    #get current web app config
    if ($isSlot) {
        Write-Verbose "We are working with slot";
        $WebAppConfig = (Get-AzureRmResource -ResourceType Microsoft.Web/sites/slots/config -ResourceName $webAppInstanceName -ResourceGroupName $resourceGroupName -ApiVersion $APIVersion);
    } else {
        Write-Verbose "We are working with web app";
        $WebAppConfig = (Get-AzureRmResource -ResourceType Microsoft.Web/sites/config -ResourceName $webAppInstanceName -ResourceGroupName $resourceGroupName -ApiVersion $APIVersion);
    }

    Write-Verbose "Web app configuration received:";
    Write-Verbose $WebAppConfig;

    $WebAppConfig.Properties.ipSecurityRestrictions = $restrictionsHashtable;
    $WebAppConfig | Set-AzureRmResource -ApiVersion $APIVersion -Force | Out-Null;
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

    SetWebAppRestrictions -ipList $ipMaskCollectionUserInput -webAppInstanceName $instanceName -resourceGroupName $rgName
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

function GetNextValueFromArray {
    param (
        [array]$array,
        [int]$currentCounter
    )

    if (($currentCounter + 1) -ge $array.Length) {
        return "-";
    }
    return $array[$currentCounter + 1];
}

#this function will split overrides
function SplitUpOverrides {
    param (
        [string]$inputString
    )

    $targetHashTable = @{};
    $temporalArr = $inputString.Split(" ",[System.StringSplitOptions]::RemoveEmptyEntries);

    for ($counter = 0; $counter -lt $temporalArr.Length; $counter++) {
        #and here start the magic, since our input data could have spaces in values (but if we have spaces in values - they have to be enclosed in double quotes)
        $key = $temporalArr[$counter].Replace("-","");
        #increment counter to get value
        $counter++;
        $value = $temporalArr[$counter];
        if ($value.StartsWith("`"") -and !$value.EndsWith("`"")) {

            $nextValue = GetNextValueFromArray -array $temporalArr -currentCounter $counter;

            #if value starts with double quote, but does not end with it - let's seek for a next value which starts with dash
            while (!$nextValue.StartsWith("-")) {
                #and collect it in our value
                $counter++;
                #we need to add space, as value was splitted on it
                $value = $value + " " + $nextValue;
                $nextValue = GetNextValueFromArray -array $temporalArr -currentCounter $counter;
            }
            #remove double quoutes within value
            $value = $value.Replace("`"","");
        } else {
            #just remove doubel quotes within value
            $value = $value.Replace("`"","");
        }
        $targetHashTable.Add($key, $value);
    }
    return $targetHashTable;
}

#Gets parameters from parameter file
function GetParametersFromParameterFile {
    param (
        [string]$filePath
    )

    if(![System.IO.File]::Exists($filePath)){
        # file with path $path doesn't exist
        Write-Host "Could not find parameters file at $filePath";
        Exit 1;
    }

    $parameters = Get-Content $filePath -Raw | ConvertFrom-Json;

    #now - test, what is in our parameters file
    if ($null -ne $parameters.parameters -and $null -eq $parameters.parameters.value) {
        #this means, that we are using default parameters file from Arm template, as it will have parameters as a collection, without value; if you you have parameter with a name "value" - then I am really sorry and I will fail here
        $parameters = $parameters.parameters;
    }

    return $parameters;
}

function SetKuduIpRestrictions {
    param (
        [string]$rgName,
        [string]$ipListSpecified
    )

    $APIVersion = GetWebAppApiVersion;
    $webApps = RetrieveAllWebApps -rgName $rgName;
    $processWebApps = $true;
    $webAppSlots = RetrieveAllWebApps -rgName $rgName -resType "Microsoft.Web/sites/slots";
    $processWebAppSlots = $true;

    #add current IP to list specified
    $clientIp = Invoke-WebRequest 'https://api.ipify.org' | Select-Object -ExpandProperty Content;
    $ipList = $ipListSpecified + "," + $clientIp + "/32";

    $restrictionsHashtable = @();
    Write-Verbose "Only following IPs will have access to KUDU of each web app: $ipList";
    $restrictionsHashtable += SplitIpStringToHashTable -ipCollectionString $ipList;


    $webAppsAmount = ($webApps | Measure-Object).Count;
    if ($webAppsAmount -le 0) {
        Write-Host "##vso[task.logissue type=warning;] SetKuduIpRestrictions: Could not retrieve any web apps in given resource group $rgName";
        $processWebApps = $false;
    }

    $webAppSlotsAmount = ($webAppSlots | Measure-Object).Count;
    if ($webAppSlotsAmount -le 0) {
        Write-Host "##vso[task.logissue type=warning;] SetKuduIpRestrictions: Could not retrieve any web app slots in given resource group $rgName";
        $processWebAppSlots = $false;
    }

    if ($processWebApps) {
        foreach($webApp in $webApps) {
            $WebAppConfig = (Get-AzureRmResource -ResourceType Microsoft.Web/sites/config -ResourceName $webApp.Name -ResourceGroupName $rgName -ApiVersion $APIVersion);
            Write-Verbose "Web app configuration received:";
            Write-Verbose $WebAppConfig;
        
            $WebAppConfig.Properties.scmIpSecurityRestrictions = $restrictionsHashtable;
            $WebAppConfig | Set-AzureRmResource -ApiVersion $APIVersion -Force | Out-Null;
        }
    }

    if ($processWebAppSlots) {
        foreach($webAppSlot in $webAppSlots) {
            $WebAppConfig = (Get-AzureRmResource -ResourceType Microsoft.Web/sites/slots/config -ResourceName $webAppSlot.Name -ResourceGroupName $rgName -ApiVersion $APIVersion);
            Write-Verbose "Web app configuration received:";
            Write-Verbose $WebAppConfig;
        
            $WebAppConfig.Properties.scmIpSecurityRestrictions = $restrictionsHashtable;
            $WebAppConfig | Set-AzureRmResource -ApiVersion $APIVersion -Force | Out-Null;
        }
    }
}
