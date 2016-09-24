if (Test-PSTestExecuting) {
    Write-Verbose 'Skipping Common Setup as it is called inside PSTest'
} else {
    Write-Verbose 'Common Setup'
    $VerbosePreference = 'Continue'
    trap { break } #This stops execution on any exception
    $ErrorActionPreference = 'Stop'

    Import-Module -Global PSTest -Force -Verbose:$false

    Remove-Item $PSScriptRoot\output\* -ea 0 -Force -Recurse
    $null = md $PSScriptRoot\output -ea 0
    cd $PSScriptRoot\output

    . ..\..\ssm\ssmcommon.ps1
}

