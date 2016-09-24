﻿# You should define before running this script.
#    $name - Name identifies logfile and test name in results
#            When running in parallel, name maps to unique ID.
#            Some thing like '0', '1', etc when running in parallel
#     $obj - This is a dictionary, used to pass output values
#            (e.g.) report the metrics back, or pass output values that will be input to subsequent functions

param ($Obj=@{})

Write-Verbose 'Executing Reboot'

. "$PSScriptRoot\Common Setup.ps1"

$startTime = Get-Date

$keyfile = Get-WinEC2KeyFile $obj.KeyPairName
$Password = Get-EC2PasswordData -InstanceId $obj.InstanceId -PemFile $keyfile -Decrypt
$securepassword = ConvertTo-SecureString $Password -AsPlainText -Force
$creds = New-Object System.Management.Automation.PSCredential ("Administrator", $securepassword)

ReStart-WinEC2Instance -NameOrInstanceIds $obj.InstanceId -Credential $creds
$obj.RestartTime = (Get-Date) - $startTime

