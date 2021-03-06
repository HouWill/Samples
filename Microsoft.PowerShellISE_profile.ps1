Import-Module "C:\Program Files (x86)\AWS Tools\PowerShell\AWSPowerShell\AWSPowerShell.psd1" -Verbose:$false

Set-DefaultAWSRegion 'us-east-1'

Function prompt { 
    $item = Get-Item (Get-Location)
    if ($item.Parent) {
        $prefix = '.../'
    } else {
        $prefix = ''
    }
    "$prefix$($item.Name)> " 
}

function sbps {
    $null = Set-PSBreakpoint -Variable StackTrace -Mode Write
}

function rbps {
    Get-PSBreakpoint -Variable StackTrace | Remove-PSBreakpoint
}


function getFile ($name, $directory, $file) {
    $dirs = @('C:\data\workspace\Samples')

    if ($file) {
        $dirs += @("$PSHOME\Modules\PSTest", "$PSHOME\Modules\PSUtil", "$PSHOME\Modules\WinEC2")
    } else {
        $dirs += @("$PSHOME\Modules")
    }

    foreach ($dir in $dirs) {
        $files = dir $dir -Include "$name" -Recurse
        if ($files) {
            return $files
        }
    }
}

function k ($pattern) {
    gps $pattern | Stop-Process -Force
}

function i ([string]$name) {
    switch ($name) 
    { 
        'ssmw' {
            c ssm
            ise '.\ssmcommon.ps1','.\Run Sequence.ps1','.\EC2 Windows Create Instance.ps1','.\Win RC RunPowerShellScript.ps1','.\Win RC InstallPowerShellModule.ps1','.\Win RC InstallApplication.ps1','.\Win RC ConfigureCloudWatch.ps1','.\EC2 Terminate Instance.ps1'
        } 
        'ssml' {
            c ssm
            ise '.\ssmcommon.ps1','.\Run Sequence.ps1','.\EC2 Linux Create Instance.ps1','.\Linux RC1 RunShellScript.ps1','.\Linux RC2 Notification.ps1','.\Linux RC3 Stress.ps1','.\EC2 Terminate Instance.ps1'
        } 
        'demol' {
            c ssm
            ise '.\ssmcommon.ps1','.\Demo Setup.ps1','.\EC2 Linux Create Instance.ps1','.\Automation 1 Lambda.ps1','.\Linux RC4 Param.ps1','.\Linux RC5 Automation.ps1','.\Inventory2 Associate.ps1','.\Maintenance Window.ps1','.\Demo Cleanup.ps1'
        } 
        default {
            $files = getFile -name $name -directory:$false -file:$true
            $files | % { ise $_.FullName}
        }
    }
}

function c ($dir) {
    $cuurentDirectory = getFile -name $dir -directory:$true -file:$false | select -First 1
    if ($cuurentDirectory) {
        cd $cuurentDirectory.FullName
    } else {
        throw "Directory $dir not found"
    }
}
