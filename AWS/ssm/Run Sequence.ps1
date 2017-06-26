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

$null = Get-SSMAssociationList | % { Remove-SSMAssociation -AssociationId $_.AssociationId -Force }
$null = Get-S3Object -BucketName 'sivaiadbucket' -Key '/ssm' | Remove-S3Object -Force


if ($EC2Linux) {
    $tests = @(
       @{
            PsTest = "..\EC2 Linux Create Instance.ps1"
            PsTestOutputKeys = @('InstanceIds', 'ImageName')
            InstanceCount = 3
            ErrorBehavior = 'SkipTests' # because if instances are not created, it does not make sense to run remaining tests
        } 
        @{
            PsTest = "..\Linux RC1 RunShellScript.ps1"
            PsTestRepeat = 20
            PsTestParallelCount = 5
        }
        @{
            PsTest = "..\Linux Associate1 with Global Document.ps1"
            PsTestParallelCount = 5
            PsTestRepeat = 1
        }
        @{
            PsTest = "..\Linux Associate2 with Custom Document.ps1"
            PsTestParallelCount = 5
            PsTestRepeat = 1
        }
        "..\Linux Associate3 Inventory.ps1"
        "..\Inventory with PutInventory and Config.ps1"
        @{
            PsTest = "..\Automation with Lambda.ps1"
            PsTestParallelCount = 5
            PsTestRepeat = 1
        }
        @{
            PsTest = "..\Linux RC2 Notification.ps1"
            PsTestParallelCount = 1#can't do parallel rightnow.
            PsTestRepeat = 1
        }
        @{
            PsTest = "..\Linux RC3 with Parameter Store.ps1"
            PsTestParallelCount = 5
            PsTestRepeat = 1
        }
   
        @{
            PsTest = "..\Linux RC4 from Automation.ps1"
            PsTestParallelCount = 5
            PsTestRepeat = 1
        }
       
        @{
            PsTest = "..\Maintenance Window.ps1"
            PsTestParallelCount = 5
            PsTestRepeat = 1
        }
        
        "..\EC2 Terminate Instance.ps1"
    )


    $perftests = @(
        @{
            PsTest = "..\EC2 Linux Create Instance.ps1"
            PsTestOutputKeys = @('InstanceIds', 'ImageName')
            InstanceCount = 1
            PsTestParallelCount = 5
            PsTestRepeat = 2
        }

        "..\ECAutomationExecution Terminate Instance.ps1"
    )


    $Parameters = @{
        Name="$($Name)ssmlinux"
        ImagePrefix='amzn-ami-hvm-*gp2'
    }

    $commonParameters = @{
        PsTestOnError='..\OnError.ps1'
        PsTestParameterSetRepeat=1
        PsTestMaxError=10
    }
    Invoke-PsTest -Test $tests -Parameters $Parameters -LogNamePrefix 'EC2 Linux' -CommonParameters $commonParameters


    if ($CFN) {
        $tests = @(
            "..\EC2 Linux Create Instance CFN1.ps1"
            "..\Automation 1 Lambda.ps1"
            "..\Inventory1.ps1"
            "..\Linux RC1 RunShellScript.ps1"
            "..\Linux RC2 Notification.ps1"
            "..\Linux RC3 Stress.ps1"
            "..\Linux RC4 Param.ps1"
            "..\Linux RC5 Automation.ps1"
            "..\EC2 Terminate Instance.ps1"
        )
        Invoke-PsTest -Test $tests -Parameters $Parameters  -Count 1 -StopOnError -LogNamePrefix 'EC2 Linux CFN1'



        $tests = @(
            "..\EC2 Linux Create Instance CFN2.ps1"
            "..\Automation 1 Lambda.ps1"
            "..\Inventory1.ps1"
            "..\Linux RC1 RunShellScript.ps1"
            "..\Linux RC2 Notification.ps1"
            "..\Linux RC3 Stress.ps1"
            "..\Linux RC4 Param.ps1"
            "..\Linux RC5 Automation.ps1"
            "..\EC2 Terminate Instance.ps1"
        )
        Invoke-PsTest -Test $tests -Parameters $Parameters  -Count 1 -StopOnError -LogNamePrefix 'EC2 Linux CFN2'
    }
}

if ($EC2Windows) {
    $tests = @(
        "..\EC2 Windows Create Instance.ps1"
        "..\Update SSM Agent.ps1"
        "..\Win RC1 RunPowerShellScript.ps1"
        "..\Win RC2 InstallPowerShellModule.ps1"
        "..\Win RC3 InstallApplication.ps1"
        "..\Win RC4 ConfigureCloudWatch.ps1"
        "..\EC2 Terminate Instance.ps1"
    )
    $Parameters = @{
        Name="$($Name)ssmwindows"
        ImagePrefix='Windows_Server-2016-English-Full-Base-20'
    }
    Invoke-PsTest -Test $tests -Parameters $Parameters  -Count 1 -StopOnError -LogNamePrefix 'EC2 Windows'
}


if ($AzureWindows) {
    $tests = @(
        "..\Azure Windows Create Instance.ps1"
        "..\Win RC1 RunPowerShellScript.ps1"
        "..\Azure Terminate Instance.ps1"
    )
    $Parameters = @{
        Name='mc-'
        ImagePrefix='Windows Server 2012 R2'
    }
    Invoke-PsTest -Test $tests -Parameters $Parameters  -Count 1 -StopOnError -LogNamePrefix 'Azure Windows'
}


if ($AzureLinux) {
    $tests = @(
        "..\Azure Linux Create Instance.ps1"
        "..\Linux RC1 RunShellScript.ps1"
        "..\Azure Terminate Instance.ps1"
    )
    $Parameters = @{
        Name='mc-'
        ImagePrefix='Ubuntu Server 14'
    }
    Invoke-PsTest -Test $tests -Parameters $Parameters  -Count 1 -StopOnError -LogNamePrefix 'Azure Linux'
}


$null = gstat

Convert-PsTestToTableFormat    


if (! (Test-PSTestExecuting)) {
 #   & "..\Cleanup.ps1"
}