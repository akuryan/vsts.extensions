#this will execute all powershell tests in repo

Import-Module $PSScriptRoot\..\buildtask\functions-module-v1.psm1
Import-Module $PSScriptRoot\test-functions.psm1

& "$PSScriptRoot\SplitUpOverrides.Tests.ps1";

& "$PSScriptRoot\GetParametersFromParameterFile.Tests.ps1"
