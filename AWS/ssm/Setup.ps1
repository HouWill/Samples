﻿#Setup once before running any test in this folder.
param ($Region = (Get-PSUtilDefaultIfNull -value (Get-DefaultAWSRegion) -defaultValue 'us-east-1'))
Write-Verbose "Region=$Region"
Set-DefaultAWSRegion $Region

$VerbosePreference = 'Continue'
Write-Verbose 'Common Setup'
$ErrorActionPreference = 'Stop'

trap { "Error [$($_.InvocationInfo.ScriptName.split('\/')[-1]):$($_.InvocationInfo.ScriptLineNumber)]: $_"; break } #This stops execution on any exception
#$endpoint = 'https://sonic.us-east-1.amazonaws.com'

$endpoint = $null

$PSDefaultParameterValues = $null
if ($endpoint) {
    $PSDefaultParameterValues = @{
        ‘*-SSM*:EndpointUrl’ = $endpoint
        ‘Invoke-AWSCLI:EndpointUrl’ = $endpoint
    } 
    Set-DefaultAWSRegion $endpoint.Split('.')[1]
} else {
    $PSDefaultParameterValues = @{
    }
}

#disable verbose setting for all functions in AWSPowerShells
foreach ($cmdinfo in (gcm -Module 'AwSPowerShell')) {
    $PSDefaultParameterValues."$($cmdinfo.Name):Verbose" = $false
}


Import-Module -Global WinEC2 -Force -Verbose:$false
Import-Module -Global PSTest -Force -Verbose:$false
. $PSScriptRoot\ssmcommon.ps1

Write-Verbose "$PSScriptRoot\output deleted"
Remove-Item $PSScriptRoot\output\* -ea 0 -Force -Recurse
$null = md $PSScriptRoot\output -ea 0


cd $PSScriptRoot\output

SSMSetTitle ''

#Remove-WinEC2Instance 'perf*' -NoWait

SSMCreateKeypair -KeyName 'test'
SSMCreateRole -RoleName 'test'
SSMCreateSecurityGroup -SecurityGroupName 'test'

