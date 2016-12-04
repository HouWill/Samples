#Setup once before running any test in this folder.
param ($Region = (Get-PSUtilDefaultIfNull -value (Get-DefaultAWSRegion) -defaultValue 'us-east-1'))
Write-Verbose "Region=$Region"
Set-DefaultAWSRegion $Region

$VerbosePreference = 'Continue'
Write-Verbose 'Common Setup'
$ErrorActionPreference = 'Stop'

trap { "Error [$($_.InvocationInfo.ScriptName.split('\/')[-1]):$($_.InvocationInfo.ScriptLineNumber)]: $_"; break } #This stops execution on any exception
#$endpoint = 'https://sonic.us-east-1.amazonaws.com'

$endpoint = $null

if ($endpoint) {
    $PSDefaultParameterValues = @{
        ‘*-SSM*:EndpointUrl’ = $endpoint
        ‘Invoke-AWSCLI:EndpointUrl’ = $endpoint
    } 
    Set-DefaultAWSRegion $endpoint.Split('.')[1]
} else {
    $PSDefaultParameterValues = $null
}



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
