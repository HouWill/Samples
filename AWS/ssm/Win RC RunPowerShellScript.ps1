# You should define before running this script.
#    $name - Name identifies logfile and test name in results
#            When running in parallel, name maps to unique ID.
#            Some thing like '0', '1', etc when running in parallel


param ($Name = 'ssm',
        $Region = (Get-PSUtilDefaultIfNull -value (Get-DefaultAWSRegion) -defaultValue 'us-east-1'))

Write-Verbose "Windows Run Command Name=$Name, Region=$Region"
Set-DefaultAWSRegion $Region

$instance = Get-WinEC2Instance $Name -DesiredState 'running'
$instanceId = $instance.InstanceId
Write-Verbose "Name=$Name InstanceId=$instanceId"


$cmd = @'

ipconfig

'@

#Run Command
Write-Verbose 'Run Command on EC2 Windows Instance'
$startTime = Get-Date
$command = SSMRunCommand  -InstanceIds $instanceId -SleepTimeInMilliSeconds 1000 `
    -Parameters @{commands=$cmd}

$obj = @{}
$obj.'CommandId' = $command
$obj.'RunCommandTime' = (Get-Date) - $startTime

Test-SSMOuput $command

return $obj