param ($Name='ssm')

Write-Verbose "Run Sequence - Name=$Name"
$host.ui.RawUI.WindowTitle = $Name

if (! (Test-PSTestExecuting)) {
    & "$PSScriptRoot\Setup.ps1"
}

Write-Verbose 'Executing Run'

$EC2Linux = $true
$EC2Windows = $true
$AzureWindows = $false

if ($EC2Linux) {
    $tests = @(
        "$PSScriptRoot\EC2 Linux Create Instance.ps1"
        "$PSScriptRoot\Linux Run Command.ps1"
        "$PSScriptRoot\EC2 Linux Terminate Instance.ps1"
    )
    $InputParameters = @{
        Name="$Name-linux"
        ImagePrefix='amzn-ami-hvm-*gp2'
    }
    Invoke-PsTest -Test $tests -InputParameters $InputParameters  -Count 3
}

if ($EC2Windows) {
    $tests = @(
        "$PSScriptRoot\EC2 Windows Create Instance.ps1"
        "$PSScriptRoot\Windows Run Command.ps1"
        "$PSScriptRoot\EC2 Windows Terminate Instance.ps1"
    )
    $InputParameters = @{
        Name="$Name-windows"
        ImagePrefix='Windows_Server-2012-R2_RTM-English-64Bit-Base-20'
    }
    Invoke-PsTest -Test $tests -InputParameters $InputParameters  -Count 1
}


if ($AzureWindows) {
    $tests = @(
        "$PSScriptRoot\Azure Windows Create Instance.ps1"
        "$PSScriptRoot\Windows Run Command.ps1"
        "$PSScriptRoot\Azure Windows Terminate Instance.ps1"
    )
    $InputParameters = @{
        Name=''
        ImagePrefix='Windows Server 2012 R2'
    }
    Invoke-PsTest -Test $tests -InputParameters $InputParameters  -Count 1
}


gstat

Convert-PsTestToTableFormat    


if (! (Test-PSTestExecuting)) {
 #   & "$PSScriptRoot\Cleanup.ps1"
}