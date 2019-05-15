# this will test a function SplitUpOverrides in functions-module-v1.psm1
Write-Host "Iteration 1";
$testString = '-templateLinkBase https://testblob.blob.core.windows.net/testcontainer/20/test/ -templateLinkAccessToken ?st=2018-01-31T08%3A26%3A47Z&se=2018-02-01T08%3A26%3A47Z&sp=r&sv=2017-03-28&sr=b&sig=7asodasdayodolasKernxyadYfcqlGZxQZU%3D -siMsDeployPackageUrl "https://testblob.blob.core.windows.net/sitecore/version/si.scwdp.zip" -cmMsDeployPackageUrl "https://testblob.blob.core.windows.net/sitecore/version/scaled/cm.scwdp.zip"';
$testHashTable1 = SplitUpOverrides -inputString $testString;
CompareValuesAndExitIfFail -value1 $testHashTable1["templateLinkBase"] -value2 "https://testblob.blob.core.windows.net/testcontainer/20/test/";
CompareValuesAndExitIfFail -value1 $testHashTable1["siMsDeployPackageUrl"] -value2 "https://testblob.blob.core.windows.net/sitecore/version/si.scwdp.zip";
CompareValuesAndExitIfFail -value1 $testHashTable1["cmMsDeployPackageUrl"] -value2 "https://testblob.blob.core.windows.net/sitecore/version/scaled/cm.scwdp.zip";

Write-Host "Iteration 2";
$testString = '-test 123 -test2 1234 -test3 "123 123"'
$testHashTable2 = SplitUpOverrides -inputString $testString;

CompareValuesAndExitIfFail -value1 $testHashTable2["test"] -value2 "123";
CompareValuesAndExitIfFail -value1 $testHashTable2["test3"] -value2 "123 123";

Write-Host "Iteration 3";
$testString = '-test 123 -test3 "123 testing spaces" -test4 "1234" -test5 "123" -test6 "1234" -test7 1234 -test8 "testing spaces again" -test9 noSpaces';
$testHashTable3 = SplitUpOverrides -inputString $testString;

CompareValuesAndExitIfFail -value1 $testHashTable3["test"] -value2 "123";
CompareValuesAndExitIfFail -value1 $testHashTable3["test3"] -value2 "123 testing spaces";
CompareValuesAndExitIfFail -value1 $testHashTable3["test4"] -value2 "1234";
CompareValuesAndExitIfFail -value1 $testHashTable3["test5"] -value2 "123";
CompareValuesAndExitIfFail -value1 $testHashTable3["test6"] -value2 "1234";
CompareValuesAndExitIfFail -value1 $testHashTable3["test7"] -value2 "1234";
CompareValuesAndExitIfFail -value1 $testHashTable3["test8"] -value2 "testing spaces again";
CompareValuesAndExitIfFail -value1 $testHashTable3["test9"] -value2 "noSpaces";
