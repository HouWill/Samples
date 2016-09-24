param ($Name)

echo $Name
$host.ui.RawUI.WindowTitle = $Name

if (! (Test-PSTestExecuting)) {
    & "$PSScriptRoot\Setup.ps1"
}

Write-Verbose 'Executing Run'


$InputParameters = @{Name=$Name}
$tests = @(
    "$PSScriptRoot\Create Instance.ps1"
    "$PSScriptRoot\Run Command.ps1"
    "$PSScriptRoot\Restart Instance.ps1"
    "$PSScriptRoot\Stop Start Instance.ps1"
    "$PSScriptRoot\Terminate Instance.ps1"
)
Invoke-PsTest -Test $tests -InputParameters $InputParameters  -Count 2

gstat

Convert-PsTestToTableFormat    


if (! (Test-PSTestExecuting)) {
    & "$PSScriptRoot\Cleanup.ps1"
}