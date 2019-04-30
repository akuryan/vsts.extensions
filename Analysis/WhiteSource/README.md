# WhiteSource scanner wrapper for Azure DevOps

[![Build status](https://dev.azure.com/dobryak/NugetsAndExtensions/_apis/build/status/AzureDevOps-Extensions/WhiteSource%20Analyzer)](https://dev.azure.com/dobryak/NugetsAndExtensions/_build/latest?definitionId=6)

This task wraps up [WhiteSource scanner configuration](https://whitesource.atlassian.net/wiki/spaces/WD/pages/686227666/Microsoft+Azure+DevOps+Services+Integration) in Powershell, by executing Powershell module, published at [NuGet](https://www.nuget.org/packages/Scanners-WhiteSource.PowerShell/)

## Script location

For reusability reason, powershell module is published as [NuGet package](https://www.nuget.org/packages/Scanners-WhiteSource.PowerShell/), sources could be reviewed at https://github.com/akuryan/Powershell.Modules/tree/master/src/Scanning/WhiteSource/tools


## Usage

Install extension at your Azure DevOps instance and configure it.

Before executing this task - restore NuGet/npm/yarn/whatever packages you have (so, your pipeline must have this steps preconfigured).

This extension is built using [WhiteSource unified agent](https://github.com/whitesource/unified-agent-distribution/blob/master/standAlone/wss-unified-agent.jar), and expects that you have either configuration file ready (you can get it [here](https://github.com/whitesource/unified-agent-distribution/blob/master/standAlone/wss-unified-agent.config)) or it will configure download and use default one.

Set up extension by filling required fields. If you wish to tailor down configuration completely - [download config file](https://github.com/whitesource/unified-agent-distribution/blob/master/standAlone/wss-unified-agent.config)) and store it in repository. If you can go with defaults - let extension to download it.

## Manual package preparation

Install [NuGet package](https://www.nuget.org/packages/Scanners-WhiteSource.PowerShell/) in temp directory. Then copy ```tools``` folder of installed package to ```ps_modules\Scanners-WhiteSource.PowerShell\```
Then, you'll be able to compile installable package for VSTS/TFS

```cmd
rem Remove all possible installations of previous module versions (if any)
for /D %f in ("%temp%\Scanners-WhiteSource.PowerShell*") do rmdir %f /s /q
rem Install module from nuget
nuget install Scanners-WhiteSource.PowerShell -OutputDirectory %Temp%
pushd %temp%\Scanners-WhiteSource.PowerShell*
rem Create directory for module
mkdir yourPathHere\ps_modules\Scanners-WhiteSource.PowerShell\tools\
rem Copy module to directory
xcopy tools\* yourPathHere\ps_modules\Scanners-WhiteSource.PowerShell\tools\ /F /S /Q /Y
popd
```
