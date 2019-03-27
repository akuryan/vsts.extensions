$forceDownloadInput = Get-VstsInput -Name forceDownload -Require;
if ($forceDownloadInput.ToLower() -eq "yes" -or $forceDownloadInput.ToLower() -eq "true") {
    $forceDownload = $true;
} else {
    $forceDownload = $false;
}
Write-Verbose "In input forceDownload we have $forceDownloadInput";
Write-Verbose "Are we going to force scanner download? $forceDownload";

$scannerTargetPath = Get-VstsInput -Name scannerTargetPath;

$projectName = Get-VstsInput -Name projectName;

$wssConfigPath = Get-VstsInput -Name wssConfigPath;

$projectVersion = Get-VstsInput -Name version;

$fileScanPattern = Get-VstsInput -Name fileScanPattern;

$wssApiKey = Get-VstsInput -Name wssApiKey;

$scanPath = Get-VstsInput -Name scanPath;

#Import module, installed as nuget
Import-Module $PSScriptRoot\ps_modules\Scanners-WhiteSource.PowerShell\tools\whitesource-scanner.psm1

Scan-Sources -ForceDownload $forceDownload -AgentPath $scannerTargetPath -ProjectName $projectName -WssConfigurationPath $wssConfigPath -Version $projectVersion -FileScanPattern $fileScanPattern -WssApiKey $wssApiKey -ScanPath $scanPath;