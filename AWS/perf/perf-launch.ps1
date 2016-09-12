#This program starts multiple PS shells in parall and
#executes perf in each of it

cd $PSScriptRoot

$VerbosePreference='Continue'
trap { break } #This stops execution on any exception
$ErrorActionPreference = 'Stop'
Import-Module -Global WinEC2 -Force 4>$null
Import-Module -Global PSTest -Force 4>$null
. ..\ssm\ssmcommon.ps1

Remove-WinEC2Instance 'perf*' -NoWait

SSMCreateKeypair -KeyName 'test'
SSMCreateRole -RoleName 'test'
SSMCreateSecurityGroup -SecurityGroupName 'test'


Invoke-PsTestLaunchInParallel -PsFileToLaunch '.\perf.ps1' `
                                     -ParallelShellCount 3 -TotalCount 6

Convert-PsTestToTableFormat

.\Output\Results.output.csv


SSMRemoveRole -RoleName 'test'
SSMRemoveKeypair -KeyName 'test'
SSMRemoveSecurityGroup -SecurityGroupName 'test'