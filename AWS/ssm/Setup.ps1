#Setup once before running any test in this folder.
param ($Region = (Get-PSUtilDefaultIfNull -value (Get-DefaultAWSRegion) -defaultValue 'us-east-1'))

Set-DefaultAWSRegion $Region

$VerbosePreference = 'Continue'
Write-Verbose 'Common Setup'
trap { break } #This stops execution on any exception
$ErrorActionPreference = 'Stop'

Import-Module -Global PSTest -Force -Verbose:$false
. $PSScriptRoot\ssmcommon.ps1

Write-Verbose "$PSScriptRoot\output deleted"
Remove-Item $PSScriptRoot\output\* -ea 0 -Force -Recurse
$null = md $PSScriptRoot\output -ea 0

cd $PSScriptRoot\output

#Remove-WinEC2Instance 'perf*' -NoWait

SSMCreateKeypair -KeyName 'test'
SSMCreateRole -RoleName 'test'
SSMCreateSecurityGroup -SecurityGroupName 'test'
