$ResourceGroupName = Get-VstsInput -Name resourceGroupName -Require
$downScaleInput = Get-VstsInput -Name downscaleSelector -Require
Write-Verbose "In input downscaleInput we have $downScaleInput"
if ($downScaleInput.ToLower() -eq "yes" -or $downScaleInput.ToLower() -eq "true") {
    #do not know why, but sometimes tasks get wrong input from pipeline
    $Downscale = $true;
} else {
    $Downscale = $false;
}

Write-Host "We are going to downscale? $Downscale"
Write-Host "Resources will be selected from $ResourceGroupName resource group"

Import-Module $PSScriptRoot\ps_modules\TlsHelper_
Add-Tls12InSession
Import-Module $PSScriptRoot\ps_modules\VstsAzureHelpers_
Initialize-Azure

#Get all resources, which are in resource groups, which contains our name
$resources = Find-AzureRmResource -ResourceGroupNameContains $ResourceGroupName

if (($resources | Measure-Object).Count -le 0)
{
    Write-Host "##vso[task.logissue type=warning;] No resources was retrieved for $ResourceGroupName"
    Exit $false
}

function ProcessWebApps {
    param ($webApps)

    $whatsProcessing = "Web app farms"
    Write-Host "Processing $whatsProcessing"
    $amount = ($webApps | Measure-Object).Count
    if ($amount -le 0) {
        Write-Host "##vso[task.logissue type=warning;] No $whatsProcessing was retrieved for $ResourceGroupName"
        return;
    }

    #hash is needed to get correct worker size
    $webAppHashSizes = @{}
    $webAppHashSizes['1'] = "Small"
    $webAppHashSizes['2'] = "Medium"
    $webAppHashSizes['3'] = "Large"
    $webAppHashSizes['4'] = "Extra Large"

    Write-Host "There is $amount $whatsProcessing to be processed."

    foreach ($farm in $webApps) {
        $resourceId = $farm.ResourceId
        $webFarmResource = Get-AzureRmResource -ResourceId $resourceId -ExpandProperties
        $resourceName = $webFarmResource.Name
        Write-Host "Performing requested operation on $resourceName"
        #get existing tags
        $tags = $webFarmResource.Tags
        if ($tags.Count -eq 0)
        {
            #there is no tags defined
            $tags = @{}
        }

        $cheaperTiers = "Free","Shared","Basic"

        if ($Downscale) {
            #we need to store current web app sizes in tags
            $tags.costsSaverTier = $webFarmResource.Sku.tier
            $tags.costsSaverNumberofWorkers = $webFarmResource.Sku.capacity
            #from time to time - workerSize returns as Default
            $tags.costsSaverWorkerSize = $webAppHashSizes[$webFarmResource.Sku.size.Substring(1,1)]
            #write tags to web app
            Set-AzureRmResource -ResourceId $resourceId -Tag $tags -Force
            (Get-AzureRmResource -ResourceId $resourceId).Tags

            #we shall proceed only if we are in more expensive tiers
            if ($cheaperTiers -notcontains $webFarmResource.Sku.tier) {
				#If web app have slots - it could not be downscaled to Basic :(
                Write-Host "Downscaling $resourceName to tier: Standard, workerSize: Small and 1 worker"
                Set-AzureRmAppServicePlan -Tier Standard -NumberofWorkers 1 -WorkerSize Small -ResourceGroupName $webFarmResource.ResourceGroupName -Name $webFarmResource.Name
            }
        }
        else {
            if ($cheaperTiers -notcontains $tags.costsSaverTier) {
                #we shall not try to set resource
                $targetTier = $tags.costsSaverTier
                $targetWorkerSize = $tags.costsSaverWorkerSize
                $targetAmountOfWorkers = $tags.costsSaverNumberofWorkers
                Write-Host "Upscaling $resourceName to tier: $targetTier, workerSize: $targetWorkerSize with $targetAmountOfWorkers workers"
                Set-AzureRmAppServicePlan -Tier $tags.costsSaverTier -NumberofWorkers $tags.costsSaverNumberofWorkers -WorkerSize $tags.costsSaverWorkerSize -ResourceGroupName $webFarmResource.ResourceGroupName -Name $webFarmResource.Name
            }
        }
    }
}

function ProcessVirtualMachines {
    param ($vms)

    $whatsProcessing = "Virtual machines"
    Write-Host "Processing $whatsProcessing"
    $amount = ($vms | Measure-Object).Count
    if ($amount -le 0) {
        Write-Host "##vso[task.logissue type=warning;] No $whatsProcessing was retrieved for $ResourceGroupName"
        return;
    }

    Write-Host "There is $amount $whatsProcessing to be processed."

    foreach ($vm in $vms) {
        $resourceName = $vm.Name
        if ($Downscale) {
            #Deprovision VMs
            Write-Host "Stopping and deprovisioning $resourceName"
            Stop-AzureRmVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Force
        }
        else {
            #Start them up
            Write-Host "Starting $resourceName"
            Start-AzureRmVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name
        }
    }
}

function ProcessSqlDatabases {
    param ($sqlServers)

    $whatsProcessing = "SQL servers"
    Write-Host "Processing $whatsProcessing"
    $amount = ($sqlServers | Measure-Object).Count
    if ($amount -le 0) {
        Write-Host "##vso[task.logissue type=warning;] No $whatsProcessing was retrieved for $ResourceGroupName"
        return;
    }

    Write-Host "There is $amount $whatsProcessing to be processed."

    foreach ($sqlServer in $sqlServers) {
        $sqlServerResourceId = $sqlServer.ResourceId
        $sqlServerResource = Get-AzureRmResource -ResourceId $sqlServerResourceId -ExpandProperties

		$sqlServerName =  $sqlServerResource.Name

        $sqlDatabases = Get-AzureRmSqlDatabase -ResourceGroupName $sqlServerResource.ResourceGroupName -ServerName $sqlServerName
        #Get existing tags for SQL server
        $sqlServerTags = $sqlServerResource.Tags
        if ($sqlServerTags.Count -eq 0)
        {
            #there is no tags defined
            $sqlServerTags = @{}
        }

        #we will store all data in one string and then we will try to save it as tags to be parsed later
        $dbNameSkuEditionInfoString = "";

        foreach ($sqlDb in $sqlDatabases.where( {$_.DatabaseName -ne "master"}))
        {
            $resourceName = $sqlDb.DatabaseName

            Write-Host "Performing requested operation on $resourceName"
            $resourceId = $sqlDb.ResourceId

            $keySku = ("{0}-{1}" -f $resourceName, "sku");
            $keyEdition = ("{0}-{1}" -f $resourceName, "edition");
            #removing possibly existing old tags
            $sqlServerTags.Remove($keySku);
            $sqlServerTags.Remove($keyEdition);
            $keySkuEdition = "skuEdition";

            if ($Downscale) {
                #proceed only in case we are not on Basic
                if ($sqlDb.Edition -ne "Basic")
                {
                    #proceed only in case we are not at S0
                    if ($sqlDb.CurrentServiceObjectiveName -ne "S0") {
                        #store it as dbName:sku-edition
                        $dbNameSkuEditionInfoString += ("{0}:{1}-{2};" -f $resourceName, $sqlDb.CurrentServiceObjectiveName, $sqlDb.Edition );

                        Write-Host "Downscaling $resourceName at server $sqlServerName to S0 size";
                        Set-AzureRmSqlDatabase -DatabaseName $resourceName -ResourceGroupName $sqlDb.ResourceGroupName -ServerName $sqlServerName -RequestedServiceObjectiveName S0 -Edition Standard;
                    } else {
                        Write-Verbose "We do not need to downscale db $resourceName at server $sqlServerName to S0 size"
                    }
                }
                #now we need to form up tags (tag have a limit of 256 chars per tag)
                $stringLength = $dbNameSkuEditionInfoString.Length;
                Write-Verbose "dbNameSkuEditionInfoString have lenght of $stringLength"
                #how much tags we need to record our databases sizes
                $tagsLimitCount = [Math]::ceiling( $stringLength/256)
                Write-Verbose "We need $tagsLimitCount tags to write our db sizes"

                #count how much tags we will have in the end
                $resultingTagsCount = $sqlServerTags.Count + $tagsLimitCount

                if ($resultingTagsCount -le 15) {
                    #we could not have more than 15 tags per resource but this is OK and we can proceed
                    for ($counter=0; $counter -lt $tagsLimitCount; $counter++){
                        $key = $keySkuEdition + $counter;
                        $value = ($dbNameSkuEditionInfoString.ToCharArray() | select -first 256) -join "";
                        #remove extracted data
                        $dbNameSkuEditionInfoString = $dbNameSkuEditionInfoString.Replace($value, "");
                        $sqlServerTags[$key] = $value
                    }
                } else {
                    Write-Host "##vso[task.logissue type=warning;] We could not save database sizes as tags, as we are over limit of 15 tags per resource on current sql server $sqlServerName. We need to write $resultingTagsCount in addition to existing tags"
                    Write-Host "##vso[task.logissue type=warning;] Databases sizes as string: $dbNameSkuEditionInfoString"
                }
            } else {
                #count keys
                $keyCounter = 0;
                foreach($key in $sqlServerTags.keys) {
                    #get all keys starting with with skuEdition
                    if ($key.Contains($keySkuEdition)){
                        $keyCounter = $keyCounter+1;
                    }
                }
                for ($counter=0; $counter -lt $keyCounter; $counter++){
                    $key = $keySkuEdition + $counter;
                    Write-Verbose "Retrieving $key from tags"
                    $dbNameSkuEditionInfoString += $sqlServerTags[$key];
                    Write-Verbose "Retrieved so far: $dbNameSkuEditionInfoString";
                }

                $databaseSizesSkuEditions = $dbNameSkuEditionInfoString.Split(';');
                $filterOn = ("{0}:*" -f $resourceName);
                $replaceString = ("{0}:" -f $resourceName);
                #get DB size and edition
                $skuEdition = ($databaseSizesSkuEditions -like $filterOn).Replace($replaceString, "");

                #ugly, a lot of branching, but could not think of any way
                if (![string]::IsNullOrWhiteSpace($skuEdition)) {
                    #we have SkuEdition defined for database, which means that it was not Basic or Standard S0 prior to downscaling
                    if ($skuEdition.Split('-').Count -eq 2)
                    {
                        #we have exactly 2 values in our tag and could proceed further
                        $edition = $skuEdition.Split('-')[1];
                        $targetSize = $skuEdition.Split('-')[0];
                        #since we could not have tags about Basic and Standard S0 databases - we are going to proceed from here
                        Write-Host "Upscaling $resourceName at server $sqlServerName to $targetSize size"
                        Set-AzureRmSqlDatabase -DatabaseName $resourceName -ResourceGroupName $sqlDb.ResourceGroupName -ServerName $sqlServerName -RequestedServiceObjectiveName $targetSize -Edition $edition
                    }
                }
            }
        }
        #Store tags on SQL server
        Set-AzureRmResource -ResourceId $sqlServerResourceId -Tag $sqlServerTags -Force
        (Get-AzureRmResource -ResourceId $sqlServerResourceId).Tags
    }
}

ProcessWebApps -webApps $resources.where( {$_.ResourceType -eq "Microsoft.Web/serverFarms" -And $_.ResourceGroupName -eq "$ResourceGroupName"})
ProcessSqlDatabases -sqlServers $resources.where( {$_.ResourceType -eq "Microsoft.Sql/servers" -And $_.ResourceGroupName -eq "$ResourceGroupName"})
ProcessVirtualMachines -vms $resources.where( {$_.ResourceType -eq "Microsoft.Compute/virtualMachines" -And $_.ResourceGroupName -eq "$ResourceGroupName"})