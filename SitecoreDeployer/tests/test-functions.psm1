function CompareValuesAndExitIfFail {
    param(
        [string]$value1,
        [string]$value2,
        $errorMessage = "Splitting up failed"
    )

    if ($value1 -ne $value2) {
        Write-Host $errorMessage;
        exit 1
    } else {
        Write-Host "Iteration OK";
    }
}