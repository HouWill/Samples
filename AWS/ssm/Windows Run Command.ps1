# You should define before running this script.
#    $name - Name identifies logfile and test name in results
#            When running in parallel, name maps to unique ID.
#            Some thing like '0', '1', etc when running in parallel
#     $obj - This is a global dictionary, used to pass output values
#            (e.g.) report the metrics back, or pass output values that will be input to subsequent functions

param ($Region = 'us-east-1', $instanceId=$instanceId)

Set-DefaultAWSRegion $Region
. "$PSScriptRoot\Common Setup.ps1"

#Run Command
Write-Verbose 'Run Command on EC2 Windows Instance'
$startTime = Get-Date
$command = SSMRunCommand  -InstanceIds $instanceId -SleepTimeInMilliSeconds 1000 `
    -Parameters @{commands='ipconfig'}
SSMDumpOutput $command

$obj.'CommandId' = $command
$obj.'RunCommandTime' = (Get-Date) - $startTime
