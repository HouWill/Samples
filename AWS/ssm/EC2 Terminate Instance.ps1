# You should define before running this script.
#    $name - Name identifies logfile and test name in results
#            When running in parallel, name maps to unique ID.
#            Some thing like '0', '1', etc when running in parallel
#     $obj - This is a global dictionary, used to pass output values
#            (e.g.) report the metrics back, or pass output values that will be input to subsequent functions

param ($Name = 'ssm', 
       $Region = (Get-PSUtilDefaultIfNull -value (Get-DefaultAWSRegion) -defaultValue 'us-east-1')
       )

Set-DefaultAWSRegion $Region

if (Get-CFNStack | ? StackName -eq $Name) {
    Write-Verbose "Removing CFN Stack $Name"
    Remove-CFNStack -StackName $Name -Force

    $cmd = { $stack = Get-CFNStack | ? StackName -eq $Name; -not $stack}

    $null = Invoke-PSUtilWait -Cmd $cmd -Message "Remove Stack $Name" -RetrySeconds 300
}

#Terminate
Write-verbose "Terminating $Name"
Remove-WinEC2Instance $Name -DesiredState 'running' -NoWait
