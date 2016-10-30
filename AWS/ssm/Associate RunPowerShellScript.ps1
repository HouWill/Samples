# You should define before running this script.
#    $name - Name identifies logfile and test name in results
#            When running in parallel, name maps to unique ID.
#            Some thing like '0', '1', etc when running in parallel


param ($Name = 'ssm-windows',
        $Region = (Get-PSUtilDefaultIfNull -value (Get-DefaultAWSRegion) -defaultValue 'us-east-1'))

Write-Verbose "Windows Run Command Name=$Name, Region=$Region"
Set-DefaultAWSRegion $Region

$instance = Get-WinEC2Instance $Name -DesiredState 'running'
$instanceId = $instance.InstanceId
Write-Verbose "Name=$Name InstanceId=$instanceId"


$cmd = @'

md c:\associate -Force -ea 0

'@

#Run Command
Write-Verbose 'Run Command on EC2 Windows Instance'
$startTime = Get-Date

$password = Get-WinEC2Password -NameOrInstanceId $instanceId

SSMAssociate -instance $instance -Parameters @{commands=$cmd} -Credential $password.Credential

$obj = @{}
$obj.'AssociateTime' = (Get-Date) - $startTime

#Test-SSMOuput $command

return $obj