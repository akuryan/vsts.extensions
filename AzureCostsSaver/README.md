# Costs saver for Azure

[![Build status](https://dev.azure.com/dobryak/NugetsAndExtensions/_apis/build/status/AzureDevOps-Extensions/AzureCostsSaver)](https://dev.azure.com/dobryak/NugetsAndExtensions/_build/latest?definitionId=5)

This package is designed to save on costs of resources in Azure. Usually, one is not using Test and Acceptance resources during nights and weekends, but not everybody can afford themselves to destroy those resources and recreate them (complex configurations, too much manual interventions, whateverYouNameIt).
So, I designed this small script for VSTS, which requires your connection to Azure RM and wants your resource group name to proceed.

If you select to downscale your resources (running at evening) - it will find all SQL databases and elastic pools, all web apps and all VMs belonging to given resource group and will downscale web apps, sql databases and elastic pools to lowest possible size, vm's will be deprovisioned. If you select to upscale resources - script will read tags on them and upscale resources (web app, sql databases and elastic pools), vm's will be started.

SQL databases sizes tags are stored on SQL server resource, as they tend to dissappear from SQL database resource.

## Script location

To improve reusability, script itself have been moved to Nuget - [package CostsSaver-Azure.PowerShell](https://www.nuget.org/packages/CostsSaver-Azure.PowerShell/); sources could be reviewed at other [repository](https://github.com/akuryan/Powershell.Modules/blob/master/src/Azure/BudgetSaver/tools/azure-costs-saver.psm1)

## Issues

1. Script will silently fail if you try to run upscaling before downscaling

1. You shall be executing at VS2017 Hosted pool, if your web apps are running on PremiumV2 tier.

1. Extension could fail if there is elastic pool with the same name as database.

## Use case

Downscale Azure resources for Testing and Acceptance environments during nights and weekends to save on costs.

### Details

Please, read [post](https://dobryak.org/saving-money-with-azure-costs-saver-vsts-extension/) detailing usage and possible use cases as well.

# Changes history

## Version 0

SQL database sizes are stored as 2 tags on SQL server resource

## Version 1

Azure imposes limitation on amount of tags per resource - 15 tags. To overcome this, sql database sizes are written as a string value, which is split to 256 chars per tag (each tag could not have more than 256 characters in value) and written to sql database server resource. On upscaling, this tags are read and size is reconstructed.

This solution was required for Sitecore 9, which deploys 14 database

## Version 2

Fixes import of AzureRM modules on agent to use latest version; changes order of tag writing and actual down-/up- scaling; added retry feature for down-/up- scaling; Web apps without slots will be downscaled to Basic during downscale action.

# Manual package preparation

Install [nuget package CostsSaver-Azure.PowerShell](https://www.nuget.org/packages/CostsSaver-Azure.PowerShell/) in temp directory. Then copy psm1 files from ```tools``` folder of installed package to ```ps_modules\CostsSaver-Azure.PowerShell\```
Then, you'll be able to compile installable package for VSTS/TFS

```cmd
rem Remove all possible installations of previous module versions (if any)
for /D %f in ("%temp%\CostsSaver-Azure.PowerShell*") do rmdir %f /s /q
rem Install module from nuget
nuget install CostsSaver-Azure.PowerShell -OutputDirectory %Temp%
pushd %temp%\CostsSaver-Azure.PowerShell*
rem Create directory for module
mkdir yourPathHere\ps_modules\buildtask\CostsSaver-Azure.PowerShell\
rem Copy module to directory
xcopy tools\azure-costs-saver.psm1 yourPathHere\ps_modules\buildtask\CostsSaver-Azure.PowerShell\ /F /S /Q /Y
popd
```