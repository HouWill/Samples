param ($Name)

echo $Name
$host.ui.RawUI.WindowTitle = $Name

if (! (Test-PSTestExecuting)) {
    . "$PSScriptRoot\Setup.ps1"
}

Write-Verbose 'Executing Run'

$tests = @(
    "$PSScriptRoot\Create Instance.ps1"
    "$PSScriptRoot\Run Command.ps1"
    "$PSScriptRoot\Restart Instance.ps1"
    "$PSScriptRoot\Stop Start Instance.ps1"
    "$PSScriptRoot\Terminate Instance.ps1"
)




$InputParametersSets = @(
    @{
        Name=$Name
        ImagePrefix='Windows_Server-2012-R2_RTM-English-64Bit-Base-COLDBOOTTEST-2016.09.14'
    },
    @{
        Name=$Name
        ImagePrefix='Windows_Server-2016-RTM-English-64Bit-Full-Base-2016.10.05'
    }
)
Invoke-PsTest -Test $tests -InputParameterSets $InputParametersSets  -Count 3 -LogNamePrefix 'Perf'


gstat

Convert-PsTestToTableFormat    


if (! (Test-PSTestExecuting)) {
    & "$PSScriptRoot\Cleanup.ps1"
}