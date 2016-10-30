# You should define before running this script.
#    $name - Name identifies logfile and test name in results
#            When running in parallel, name maps to unique ID.
#            Some thing like '0', '1', etc when running in parallel
#     $obj - This is a global dictionary, used to pass output values
#            (e.g.) report the metrics back, or pass output values that will be input to subsequent functions

param ($Name = "ssm-linux", 
    $Region = (Get-PSUtilDefaultIfNull -value (Get-DefaultAWSRegion) -defaultValue 'us-east-1'))

Set-DefaultAWSRegion $Region

$instance = Get-WinEC2Instance $Name -DesiredState 'running'
$instanceId = $instance.InstanceId
Write-Verbose "Name=$Name InstanceId=$instanceId"


#Run Command
Write-Verbose 'Run Command on EC2 Windows Instance'
$startTime = Get-Date
$command = SSMRunCommand -InstanceIds $instanceId -SleepTimeInMilliSeconds 1000 `
    -DocumentName 'AWS-RunShellScript' -Parameters @{commands='ifconfig'}

Test-SSMOuput $command

$obj = @{}
$obj.'CommandId' = $command.CommandId
$obj.'RunCommandTime' = (Get-Date) - $startTime

return $obj