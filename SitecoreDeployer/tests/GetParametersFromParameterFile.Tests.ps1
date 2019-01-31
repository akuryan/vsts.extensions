# this will test a function GetParametersFromParameterFile in functions-module-v1.psm1

$files = "$PSScriptRoot\tests-files\paramsRetrieval\azuredeploy.parameters.altered.json", "$PSScriptRoot\tests-files\paramsRetrieval\azuredeploy.parameters.default.json", "$PSScriptRoot\tests-files\paramsRetrieval\azuredeploy.parameters.test2.json", "$PSScriptRoot\tests-files\paramsRetrieval\azuredeploy.parameters.test3.json";

foreach ($file in $files) {
    $filePath = Resolve-Path -Path $file;
    $params = GetParametersFromParameterFile -filePath $filePath;
    CompareValuesAndExitIfFail -value1 $params.licenseXml.value -value2 "testValue" -errorMessage "Value retrieved incorrectly";
}