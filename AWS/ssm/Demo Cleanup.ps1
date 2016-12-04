﻿Write-Verbose "Demo Cleanup"
$host.ui.RawUI.WindowTitle = $Name

if (! (Test-PSTestExecuting)) {
    . "$PSScriptRoot\Setup.ps1"
}

Write-Verbose 'Executing Demo Setup'

$tests = @(
    #"$PSScriptRoot\EC2 Linux Create Instance.ps1"
    "$PSScriptRoot\Maintenance Window.ps1"
    "$PSScriptRoot\Automation 1 Lambda.ps1"
    "$PSScriptRoot\Linux RC4 Param.ps1"
    "$PSScriptRoot\Linux RC5 Automation.ps1"
    "$PSScriptRoot\Inventory2 Associate.ps1"
    "$PSScriptRoot\EC2 Terminate Instance.ps1"
)
$InputParameters = @{
    Name="Linux"
    SetupAction='CleanupOnly'
    ImagePrefix='amzn-ami-hvm-*gp2'
}
Invoke-PsTest -Test $tests -InputParameters $InputParameters  -Count 1 -StopOnError -LogNamePrefix 'EC2 Linux'


$tests = @(
    "$PSScriptRoot\Inventory2 Associate.ps1"
    "$PSScriptRoot\EC2 Terminate Instance.ps1"
)
$InputParameters = @{
    Name="Windows"
    SetupAction='CleanupOnly'
    ImagePrefix='Windows_Server-2016-English-Full-Base-20'
}
Invoke-PsTest -Test $tests -InputParameters $InputParameters  -Count 1 -StopOnError -LogNamePrefix 'EC2 Windows'
