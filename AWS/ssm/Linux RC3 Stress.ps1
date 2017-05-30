#Invokes $Count # of Run Commands, then waits for them to complete
#It iterates for $IterationCount # of times.
param (
    $Name = (Get-PSUtilDefaultIfNull -value $Name -defaultValue 'ssmlinux'), 
    $InstanceIds = $InstanceIds,
    $IterationCount=2, # Number of times to repeat
    $Count=5, # Number of send commands in sequence before checking for results
    $Region = (Get-PSUtilDefaultIfNull -value (Get-DefaultAWSRegion) -defaultValue 'us-east-1')
    )

Set-DefaultAWSRegion $Region

if ($InstanceIds.Count -eq 0) {
    Write-Verbose "InstanceIds is empty, retreiving instance with Name=$Name"
    $InstanceIds = (Get-WinEC2Instance $Name -DesiredState 'running').InstanceId
}
Write-Verbose "Linux RC Stress: Name=$Name, InstanceId=$instanceIds, Count=$Count, IterationCount=$IterationCount"


function SSMTestRunCommand ([string[]]$InstanceIds, [int]$Count=1) {
    Get-Date
    Write-Verbose "SSMTestRunCommand: InstanceIds=$InstanceIds, Count=$Count"

    $results = @()

    for($i=0; $i -lt $Count; $i++) {
        
        $result = Send-SSMCommand -InstanceIds $InstanceIds -DocumentName 'AWS-RunShellScript' -Parameters @{commands='ifconfig'}
        #$result = (aws ssm send-command --targets Key=tag:Name,Values=$Name --document-name 'AWS-RunShellScript' --parameters commands=ifconfig --endpoint-url $endpoint | ConvertFrom-Json).Command
        $results += $result
        Write-Verbose "Sent command i=$i CommandId=$($result.CommandId), InstanceId=$InstanceIds"
    }

    foreach ($result in $results) {
        Write-Verbose "Wait for completion CommandId=$($result.CommandId), InstanceId=$InstanceIds"
        $cmd = {
            $status1 = (Get-SSMCommand -CommandId $result.CommandId).Status
            ($status1 -ne 'Pending' -and $status1 -ne 'InProgress')
        }
        $null = Invoke-PsUtilWait -Cmd $cmd -Message "Command Execution for CommandId=$($result.CommandId)" -RetrySeconds 300 -SleepTimeInMilliSeconds 2000
    
        $command = Get-SSMCommand -CommandId $result.CommandId
        if ($result.CommandId -ne $command.CommandId) {
            throw "CommandId mismatch. Expected=($result.CommandId), Got=$($command.CommandId), Status=$($command.Status)"
        }
        if ($command.Status -ne 'Success') {
            throw "Command $($command.CommandId) did not succeed, Status=$($command.Status)"
        }

        foreach ($instanceId in $InstanceIds) {
            $invocation = Get-SSMCommandInvocation -InstanceId $InstanceId -CommandId $command.CommandId -Details:$true
            $output = $invocation.CommandPlugins[0].Output
            Write-Verbose "SSMTestRunCommand InstanceId=$instanceId, Output Len=$($output.Length)"
            if ($output.Length -lt 800) {
                throw "Output length less than 800"
            }
        }
    }
}

for ($iteration=1; $iteration -le $IterationCount; $iteration++) {
    Write-Host "Iteration=$iteration" -ForegroundColor Yellow

    SSMTestRunCommand $InstanceIds -Count $Count
}
