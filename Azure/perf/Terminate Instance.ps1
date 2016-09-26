# You should define before running this script.
#    $name - Name identifies logfile and test name in results
#            When running in parallel, name maps to unique ID.
#            Some thing like '0', '1', etc when running in parallel
#     $obj - This is a dictionary, used to pass output values
#            (e.g.) report the metrics back, or pass output values that will be input to subsequent functions

param ($ServiceName = '', $Obj=@{})

Write-Verbose "Terminating $serviceName"
if ($ServiceName.Length -eq 0) {
    throw "ServiceName can't be empty"
}

$startTime = Get-Date
Remove-AzureService -ServiceName $serviceName -DeleteAll -Force
$terminateTime = Get-Date
Write-Verbose "$($terminateTime - $startTime) - Terminate"

$Obj.'TerminateTime' = $terminateTime - $startTime

#No easy way to find the boot diagnostics container. This is a workaround
foreach ($container in (Get-AzureStorageContainer)) {
    $count = (Get-AzureStorageBlob -Container $container.Name | ? Name -like "*$serviceName*" | measure).Count

    if ($count -gt 0) { # This container has some blobs created.
        Write-Verbose "Remove blobs from Container $($container.Name)"
        Get-AzureStorageContainer -Container $container.Name | Get-AzureStorageBlob | 
            where { $_.Name -like "*$serviceName*" -and -not ($_.Name -like '*.vhd') } | Remove-AzureStorageBlob -Force

        if ($container.Name -like 'bootdiagnostics*' -and 
                    (Get-AzureStorageBlob -Container $container.Name | measure).Count -eq 0) {
            Write-Verbose "Remove Container $($container.Name)"
            Remove-AzureStorageContainer -Container $container.Name 
        }
    }
}