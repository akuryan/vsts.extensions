# WhiteSource scanner wrapper for Azure DevOps

This task wraps up [WhiteSource scanner configuration](https://whitesource.atlassian.net/wiki/spaces/WD/pages/686227666/Microsoft+Azure+DevOps+Services+Integration) in Powershell, by executing Powershell module, published at [NuGet](https://www.nuget.org/packages/Scanners-WhiteSource.PowerShell/)

## Script location

For reusability reason, powershell module is published as [NuGet package](https://www.nuget.org/packages/Scanners-WhiteSource.PowerShell/), sources could be reviewed at https://github.com/akuryan/Powershell.Modules/tree/master/src/Scanning/WhiteSource/tools


## Usage

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
