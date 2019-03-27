$forceDownloadInput = Get-VstsInput -Name forceDownload -Require;
if ($forceDownloadInput.ToLower() -eq "yes" -or $forceDownloadInput.ToLower() -eq "true") {
    $forceDownload = $true;
} else {
    $forceDownload = $false;
}
Write-Verbose "In input forceDownload we have $forceDownloadInput";
Write-Verbose "Are we going to force scanner download? $forceDownload";

$scannerTargetPath = Get-VstsInput -Name scannerTargetPath;

$wssConfigPath = Get-VstsInput -Name wssConfigPath;

$projectName = Get-VstsInput -Name projectName;



