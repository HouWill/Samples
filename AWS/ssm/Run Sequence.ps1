param (
    $Name=$null,
    [switch]$EC2Linux = $true,
    [switch]$EC2Windows = $false,
    [switch]$AzureWindows = $false,
    [switch]$AzureLinux = $false,
    [switch]$CFN = $false
)

Write-Verbose "Run Sequence - Name=$Name, EC2Linux=$EC2Linux, EC2Windows=$EC2Windows, AzureWindows=$AzureWindows, AzureLinux=$AzureLinux"
$host.ui.RawUI.WindowTitle = $Name

if (! (Test-PSTestExecuting)) {
    . "$PSScriptRoot\Setup.ps1"
}

Write-Verbose 'Executing Run'

if ($EC2Linux) {
    $tests = @(
        @{
            Test = "$PSScriptRoot\EC2 Linux Create Instance.ps1"
            Output = @('InstanceIds', 'ImageName')
        }
        "$PSScriptRoot\Automation 1 Lambda.ps1"
        "$PSScriptRoot\Inventory1.ps1"
        "$PSScriptRoot\Linux RC1 RunShellScript.ps1"
        "$PSScriptRoot\Linux RC2 Notification.ps1"
        "$PSScriptRoot\Linux RC3 Stress.ps1"
        "$PSScriptRoot\Linux RC4 Param.ps1"
        "$PSScriptRoot\Linux RC5 Automation.ps1"
        "$PSScriptRoot\Linux Associate1 Simple.ps1"
        "$PSScriptRoot\Linux Associate2 Inventory.ps1"
        "$PSScriptRoot\Maintenance Window.ps1"
        "$PSScriptRoot\EC2 Terminate Instance.ps1"
    )
    $InputParameters = @{
        Name="$($Name)ssmlinux"
        ImagePrefix='amzn-ami-hvm-*gp2'
    }
    Invoke-PsTest -Test $tests -InputParameters $InputParameters  -OuterRepeat 2 -StopOnError -LogNamePrefix 'EC2 Linux'


    if ($CFN) {
        $tests = @(
            "$PSScriptRoot\EC2 Linux Create Instance CFN1.ps1"
            "$PSScriptRoot\Automation 1 Lambda.ps1"
            "$PSScriptRoot\Inventory1.ps1"
            "$PSScriptRoot\Linux RC1 RunShellScript.ps1"
            "$PSScriptRoot\Linux RC2 Notification.ps1"
            "$PSScriptRoot\Linux RC3 Stress.ps1"
            "$PSScriptRoot\Linux RC4 Param.ps1"
            "$PSScriptRoot\Linux RC5 Automation.ps1"
            "$PSScriptRoot\EC2 Terminate Instance.ps1"
        )
        Invoke-PsTest -Test $tests -InputParameters $InputParameters  -Count 1 -StopOnError -LogNamePrefix 'EC2 Linux CFN1'



        $tests = @(
            "$PSScriptRoot\EC2 Linux Create Instance CFN2.ps1"
            "$PSScriptRoot\Automation 1 Lambda.ps1"
            "$PSScriptRoot\Inventory1.ps1"
            "$PSScriptRoot\Linux RC1 RunShellScript.ps1"
            "$PSScriptRoot\Linux RC2 Notification.ps1"
            "$PSScriptRoot\Linux RC3 Stress.ps1"
            "$PSScriptRoot\Linux RC4 Param.ps1"
            "$PSScriptRoot\Linux RC5 Automation.ps1"
            "$PSScriptRoot\EC2 Terminate Instance.ps1"
        )
        Invoke-PsTest -Test $tests -InputParameters $InputParameters  -Count 1 -StopOnError -LogNamePrefix 'EC2 Linux CFN2'
    }
}

if ($EC2Windows) {
    $tests = @(
        "$PSScriptRoot\EC2 Windows Create Instance.ps1"
        "$PSScriptRoot\Update SSM Agent.ps1"
        "$PSScriptRoot\Win RC1 RunPowerShellScript.ps1"
        "$PSScriptRoot\Win RC2 InstallPowerShellModule.ps1"
        "$PSScriptRoot\Win RC3 InstallApplication.ps1"
        "$PSScriptRoot\Win RC4 ConfigureCloudWatch.ps1"
        "$PSScriptRoot\EC2 Terminate Instance.ps1"
    )
    $InputParameters = @{
        Name="$($Name)ssmwindows"
        ImagePrefix='Windows_Server-2016-English-Full-Base-20'
    }
    Invoke-PsTest -Test $tests -InputParameters $InputParameters  -Count 1 -StopOnError -LogNamePrefix 'EC2 Windows'
}


if ($AzureWindows) {
    $tests = @(
        "$PSScriptRoot\Azure Windows Create Instance.ps1"
        "$PSScriptRoot\Win RC1 RunPowerShellScript.ps1"
        "$PSScriptRoot\Azure Terminate Instance.ps1"
    )
    $InputParameters = @{
        Name='mc-'
        ImagePrefix='Windows Server 2012 R2'
    }
    Invoke-PsTest -Test $tests -InputParameters $InputParameters  -Count 1 -StopOnError -LogNamePrefix 'Azure Windows'
}


if ($AzureLinux) {
    $tests = @(
        "$PSScriptRoot\Azure Linux Create Instance.ps1"
        "$PSScriptRoot\Linux RC1 RunShellScript.ps1"
        "$PSScriptRoot\Azure Terminate Instance.ps1"
    )
    $InputParameters = @{
        Name='mc-'
        ImagePrefix='Ubuntu Server 14'
    }
    Invoke-PsTest -Test $tests -InputParameters $InputParameters  -Count 1 -StopOnError -LogNamePrefix 'Azure Linux'
}


gstat

Convert-PsTestToTableFormat    


if (! (Test-PSTestExecuting)) {
 #   & "$PSScriptRoot\Cleanup.ps1"
}