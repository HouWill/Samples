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
            PsTest = "$PSScriptRoot\EC2 Linux Create Instance.ps1"
            PsTestOutputKeys = @('InstanceIds', 'ImageName')
            InstanceCount = 3
        }
        
        
        @{
            PsTest = "$PSScriptRoot\Linux RC1 RunShellScript.ps1"
            PsTestRepeat = 2
            PsTestParallelCount = 3
        }
        @{
            PsTest = "$PSScriptRoot\Linux Associate1 with Global Document.ps1"
            PsTestParallelCount = 5
            PsTestRepeat = 1
        }
        @{
            PsTest = "$PSScriptRoot\Linux Associate2 with Custom Document.ps1"
            PsTestParallelCount = 5
            PsTestRepeat = 1
        }
        "$PSScriptRoot\Linux Associate3 Inventory.ps1"
        "$PSScriptRoot\Inventory with PutInventory and Config.ps1"
        @{
            PsTest = "$PSScriptRoot\Automation with Lambda.ps1"
            PsTestParallelCount = 5
            PsTestRepeat = 1
        }
        @{
            PsTest = "$PSScriptRoot\Linux RC2 Notification.ps1"
            PsTestParallelCount = 1#can't do parallel rightnow.
            PsTestRepeat = 1
        }
        @{
            PsTest = "$PSScriptRoot\Linux RC3 with Parameter Store.ps1"
            PsTestParallelCount = 5
            PsTestRepeat = 1
        }
   
        @{
            PsTest = "$PSScriptRoot\Linux RC4 from Automation.ps1"
            PsTestParallelCount = 5
            PsTestRepeat = 1
        }
       
        @{
            PsTest = "$PSScriptRoot\Maintenance Window.ps1"
            PsTestParallelCount = 5
            PsTestRepeat = 1
        }
        
        "$PSScriptRoot\EC2 Terminate Instance.ps1"
    )

    $Parameters = @{
        Name="$($Name)ssmlinux"
        ImagePrefix='amzn-ami-hvm-*gp2'

       # PsTestParameterSetRepeat=3
        PsTestStopOnError=$true
    }


    Invoke-PsTest -Test $tests -Parameters $Parameters -LogNamePrefix 'EC2 Linux' 


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
        Invoke-PsTest -Test $tests -Parameters $Parameters  -Count 1 -StopOnError -LogNamePrefix 'EC2 Linux CFN1'



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
        Invoke-PsTest -Test $tests -Parameters $Parameters  -Count 1 -StopOnError -LogNamePrefix 'EC2 Linux CFN2'
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
    $Parameters = @{
        Name="$($Name)ssmwindows"
        ImagePrefix='Windows_Server-2016-English-Full-Base-20'
    }
    Invoke-PsTest -Test $tests -Parameters $Parameters  -Count 1 -StopOnError -LogNamePrefix 'EC2 Windows'
}


if ($AzureWindows) {
    $tests = @(
        "$PSScriptRoot\Azure Windows Create Instance.ps1"
        "$PSScriptRoot\Win RC1 RunPowerShellScript.ps1"
        "$PSScriptRoot\Azure Terminate Instance.ps1"
    )
    $Parameters = @{
        Name='mc-'
        ImagePrefix='Windows Server 2012 R2'
    }
    Invoke-PsTest -Test $tests -Parameters $Parameters  -Count 1 -StopOnError -LogNamePrefix 'Azure Windows'
}


if ($AzureLinux) {
    $tests = @(
        "$PSScriptRoot\Azure Linux Create Instance.ps1"
        "$PSScriptRoot\Linux RC1 RunShellScript.ps1"
        "$PSScriptRoot\Azure Terminate Instance.ps1"
    )
    $Parameters = @{
        Name='mc-'
        ImagePrefix='Ubuntu Server 14'
    }
    Invoke-PsTest -Test $tests -Parameters $Parameters  -Count 1 -StopOnError -LogNamePrefix 'Azure Linux'
}


gstat

Convert-PsTestToTableFormat    


if (! (Test-PSTestExecuting)) {
 #   & "$PSScriptRoot\Cleanup.ps1"
}