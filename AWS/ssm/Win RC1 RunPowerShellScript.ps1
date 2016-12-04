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
Write-Verbose "Windows RC1 RunPowerShellScript: Name=$Name, InstanceId=$instanceIds"


$cmd = @'

ipconfig

'@

#Run Command
Write-Verbose 'Run Command on EC2 Windows Instance'
$startTime = Get-Date
$command = SSMRunCommand  -InstanceIds $InstanceIds -SleepTimeInMilliSeconds 1000 -Parameters @{commands=$cmd}

$obj = @{}
$obj.'CommandId' = $command
$obj.'RunCommandTime' = (Get-Date) - $startTime

Test-SSMOuput $command

return $obj