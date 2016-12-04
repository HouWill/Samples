param (
    $Name = (Get-PSUtilDefaultIfNull -value $Name -defaultValue 'ssmlinux'), 
    $InstanceIds = $InstanceIds,
    $Region = (Get-PSUtilDefaultIfNull -value (Get-DefaultAWSRegion) -defaultValue 'us-east-1')
    )

Set-DefaultAWSRegion $Region

if ($InstanceIds.Count -eq 0) {
    Write-Verbose "InstanceIds is empty, retreiving instance with Name=$Name"
    $InstanceIds = (Get-WinEC2Instance $Name -DesiredState 'running').InstanceId
}
Write-Verbose "Update SSM Agent: Name=$Name, InstanceId=$instanceIds"


#Run Command
$startTime = Get-Date
$command = SSMRunCommand  -InstanceIds $InstanceIds -DocumentName 'AWS-UpdateSSMAgent' -SleepTimeInMilliSeconds 1000

$obj = @{}
$obj.'CommandId' = $command
$obj.'RunCommandTime' = (Get-Date) - $startTime

Test-SSMOuput $command

return $obj