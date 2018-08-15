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

#Import module, installed as nuget
Import-Module $PSScriptRoot\ps_modules\CostsSaver-Azure.PowerShell\azure-costs-saver.psm1

Set-ResourceSizesForCostsSaving -ResourceGroupName $ResourceGroupName -Downscale $Downscale -executionEnv "vsts"