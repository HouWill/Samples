try
{
    "Instance Type`tRegion`tRunning`tPing`tPassword`tRemote`tTerminate" > c:\temp\perf.csv
}
catch
{
    Write-Host 'not able to create c:\temp\perf.csv' -ForegroundColor Red
    return
}

$regions = Get-AWSRegion


while ($true)
{
    foreach ($region in $regions)
    {
        Write-Host '-----------------------'
        Write-Host $region.Region -ForegroundColor Yellow
        Write-Host '-----------------------'

        . "$PSScriptRoot\EC2.ps1" -Region $region.Region -InstanceType "m3.medium"
    }
}