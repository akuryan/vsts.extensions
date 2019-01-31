function CompareValuesAndExitIfFail {
    param(
        [string]$value1,
        [string]$value2
    )

    if ($value1 -ne $value2) {
        Write-Host "Splitting up failed"
        exit 1
    } else {
        Write-Host "Iteration OK";
    }
}