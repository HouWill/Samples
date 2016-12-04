param (
    $Name = (Get-PSUtilDefaultIfNull -value $Name -defaultValue 'ssmlinux'), 
    $InstanceIds = $InstanceIds,
    $Region = (Get-PSUtilDefaultIfNull -value (Get-DefaultAWSRegion) -defaultValue 'us-east-1'),
    [string] $SetupAction = ''  # SetupOnly or CleanupOnly
    )

Set-DefaultAWSRegion $Region

if ($InstanceIds.Count -eq 0) {
    Write-Verbose "InstanceIds is empty, retreiving instance with Name=$Name"
    $InstanceIds = (Get-WinEC2Instance $Name -DesiredState 'running').InstanceId
}
Write-Verbose "Maintenance Window: Name=$Name, InstanceId=$instanceIds, SetupAction=$SetupAction"

$ErrorActionPreference='continue'
$MWName = "$($Name)-MW-Every-Five-Min"

$window = Get-SSMMaintenanceWindowList -Filter @{Key='Name';Values=$MWName}
if ($window) {
    Write-Verbose "Removing Maintenance Window $($window.Name), WindowId=$($window.WindowId)"
    Remove-SSMMaintenanceWindow -WindowId $window.WindowId -Force
}

if ($SetupAction -eq 'CleanupOnly') {
    return
} 

$windowId = New-SSMMaintenanceWindow -Name $MWName -Schedule 'cron(0 0/5 * 1/1 * ? *)' -Duration 2 -Cutoff 1 -AllowUnassociatedTarget $true

$a = New-Object 'Amazon.SimpleSystemsManagement.Model.MaintenanceWindowTaskParameterValueExpression'
$a.Values.Add('ifconfig')

$windowTaskId = Register-SSMTaskWithMaintenanceWindow -WindowId $windowId -Target @{Key='InstanceIds';Values=$InstanceIds} `
        -ServiceRoleArn 'arn:aws:iam::660454403809:role/AMIA' `
        -TaskType RUN_COMMAND -TaskArn 'AWS-RunShellScript'  -TaskParameter @{commands=[Amazon.SimpleSystemsManagement.Model.MaintenanceWindowTaskParameterValueExpression]$a} `
        -MaxConcurrency 1 -MaxError 1 -Priority 0


if ($SetupAction -eq 'SetupOnly') {
    return
}       
        
$cmd = { Get-SSMMaintenanceWindowExecutionList -WindowId $windowId | select -Last 1 }
$execution = Invoke-PSUtilWait -Cmd $cmd 'MW Execution' -RetrySeconds 500 -PrintVerbose -SleepTimeInMilliSeconds 10000

$cmd = {
    $a = Get-SSMMaintenanceWindowExecutionTaskList -WindowExecutionId $execution.WindowExecutionId
    if ($a.Status -notlike '*PROGRESS') {
        $a
    }
}
$taskexecution = Invoke-PSUtilWait -Cmd $cmd 'MW Task Complete' 


$taskinvocation = Get-SSMMaintenanceWindowExecutionTaskInvocationList -WindowExecutionId $execution.WindowExecutionId -TaskId $taskexecution.TaskExecutionId

$command = Get-SSMCommand -CommandId $taskinvocation.ExecutionId

Test-SSMOuput $command

#Get-SSMMaintenanceWindowExecutionTask -WindowExecutionId $execution.WindowExecutionId -TaskId $taskexecution.TaskExecutionId

Unregister-SSMTaskFromMaintenanceWindow -WindowId $windowId -WindowTaskId $windowTaskId

Remove-SSMMaintenanceWindow -WindowId $windowId -Force
