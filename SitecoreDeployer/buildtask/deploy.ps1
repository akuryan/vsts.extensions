#getting data from task
$ArmTemplatePath = Get-VstsInput -Name armTemplatePath -Require
$ArmParametersPath = Get-VstsInput -Name armParametersPath -Require
$RgName = Get-VstsInput -Name resourceGroupName -Require
$location = Get-VstsInput -Name location -Require
$DeploymentType = Get-VstsInput -Name deploymentType -Require
#get input for generate SAS
$generateSasInput = Get-VstsInput -Name generateSas -Require
#convert it to Boolean
$GenerateSas = [System.Convert]::ToBoolean($generateSasInput)
#get license location
$licenseLocation = Get-VstsInput -Name licenseLocation -Require

Import-Module $PSScriptRoot\ps_modules\VstsAzureHelpers_
Initialize-Azure

Import-Module $PSScriptRoot\functions-module-v1.psm1
#region Create Params Object
# license file needs to be secure string and adding the params as a hashtable is the only way to do it
$additionalParams = New-Object -TypeName Hashtable;

$params = Get-Content $ArmParametersPath -Raw | ConvertFrom-Json;

foreach($p in $params | Get-Member -MemberType *Property) {
	# Check if the parameter is a reference to a Key Vault secret
	if (($params.$($p.Name).reference) -and
		($params.$($p.Name).reference.keyVault) -and
		($params.$($p.Name).reference.keyVault.id) -and
		($params.$($p.Name).reference.secretName)){
		$vaultName = Split-Path $params.$($p.Name).reference.keyVault.id -Leaf
        $secretName = $params.$($p.Name).reference.secretName
        if (CheckIfPossiblyUriAndIfNeedToGenerateSas -name $p.Name -generate $GenerateSas) {
            #if parameter name contains msdeploy or url - it is great point of deal that we have URL to our package here
            $secret = TryGenerateSas -maybeStorageUri (Get-AzureKeyVaultSecret -VaultName $vaultName -Name $secretName).SecretValueText
            Write-Debug "URI text is $secret"
        } else {
            $secret = (Get-AzureKeyVaultSecret -VaultName $vaultName -Name $secretName).SecretValue
        }

		$additionalParams.Add($p.Name, $secret);
	} else {
        # or a normal plain text parameter
        if (CheckIfPossiblyUriAndIfNeedToGenerateSas -name $p.Name -generate $GenerateSas) {
            $tempUrlForMessage = $params.$($p.Name).value
            Write-Verbose "We are going to generate SAS for $tempUrlForMessage"
            #process replacement here
            $valueToAdd = TryGenerateSas -maybeStorageUri $params.$($p.Name).value
            $additionalParams.Add($p.Name, $valueToAdd);
            Write-Verbose "URI text is $valueToAdd"
        } else {
            $additionalParams.Add($p.Name, $params.$($p.Name).value);
        }
	}
}

Write-Verbose "Do we need to generate SAS? $GenerateSas"
foreach($key in $additionalParams.keys)
{
    $message = '{0} is {1}' -f $key, $additionalParams[$key]
    Write-Verbose $message
}

if ($DeploymentType -eq "infra") {
    $additionalParams.Set_Item('deploymentId', $RgName);
} else {
    #now, tricky part = get license.xml content
    if ($licenseLocation -ne "none") {
        #license file is not defined in template
        if ($licenseLocation -eq "inline") {
            #license is added to VSTS release settings
            $licenseFileContent = Get-VstsInput -Name inlineLicense -Require
        }
        if ($licenseLocation -eq "filesystem") {
                # read the contents of your Sitecore license file
                $licenseFsPath = Get-VstsInput -Name pathToLicense -Require
                $licenseFileContent = Get-Content -Raw -Encoding UTF8 -Path $licenseFsPath | Out-String;
        }
        if ($licenseLocation -eq "url") {
            #read license from URL
            $licenseUriInput = Get-VstsInput -Name urlToLicense -Require
            if ($GenerateSas) {
                #trying to generate SAS
                $licenseUri = TryGenerateSas -maybeStorageUri $licenseUriInput
            } else {
                $licenseUri = $licenseUriInput
            }
            Write-Verbose "We are going to download license from $licenseUri"
            $wc = New-Object System.Net.WebClient
            $wc.Encoding = [System.Text.Encoding]::UTF8
            $licenseFileContent =  $wc.DownloadString($licenseUri)
        }
        #we shall update ARM template parameters only in case it is defined on VSTS level
        $additionalParams.Set_Item('licenseXml', $licenseFileContent);
    }
}

#endregion

try {

    Write-Host "Check if resource group already exists..."
    $notPresent = Get-AzureRmResourceGroup -Name $RgName -ev notPresent -ea 0;

    if (!$notPresent)
    {
        if ($DeploymentType -ne "infra")
        {
            #if it is not an infra deployment - than we shall throw error
            throw "Resource group is not present, exiting"
        }
        New-AzureRmResourceGroup -Name $RgName -Location $location;
    }

    Write-Verbose "Starting ARM deployment...";

    if ($DeploymentType -eq "infra") {
        $deploymentName = "sitecore-infra"
        New-AzureRmResourceGroupDeployment -Name $deploymentName -ResourceGroupName $RgName -TemplateFile $ArmTemplatePath -TemplateParameterObject $additionalParams;
    } else {
        #deployment name is used to generate login to SQL as well - so for msdeploy and redeploy it shall be equal
        $deploymentName = "sitecore-msdeploy"
        # Fetch output parameters from Sitecore ARM deployment as authoritative source for the rest of web deploy params
        $sitecoreDeployment = Get-AzureRmResourceGroupDeployment -ResourceGroupName $RgName -Name "sitecore-infra"
        $sitecoreDeploymentOutput = $sitecoreDeployment.Outputs
        $sitecoreDeploymentOutputAsJson =  ConvertTo-Json $sitecoreDeploymentOutput -Depth 5
        $sitecoreDeploymentOutputAsHashTable = ConvertPSObjectToHashtable $(ConvertFrom-Json $sitecoreDeploymentOutputAsJson)

        New-AzureRmResourceGroupDeployment -Name $deploymentName -ResourceGroupName $RgName -TemplateFile $ArmTemplatePath -TemplateParameterObject $additionalParams -provisioningOutput $sitecoreDeploymentOutputAsHashTable;
    }

    Write-Host "Deployment Complete.";
}
catch {
    Write-Error $_.Exception.Message
    Break
}
