Import-Module $PSScriptRoot\test.psm1 -Force

cd C:\workspace

function glog ()
{
    notepad C:\workspace\EC2-Windows-AWSDriverUpgrader\src\DriverUpgrader\bin\Debug\AWSDriverUpgradeLog.txt
}

function push ()
{
       # robocopy c:\workspace \\tsclient\d\data\workspace /mir
    robocopy c:\workspace \\tsclient\c\data\workspace /mir
}

function pull ()
{
       # robocopy c:\workspace \\tsclient\d\data\workspace /mir
    robocopy \\tsclient\c\data\workspace c:\workspace /mir
}

function debug ()
{
     cd C:\workspace\EC2-Windows-AWSDriverUpgrader\src\DriverUpgrader\bin\Debug
}



Set-DefaultAWSRegion $DefaultRegion
$dumproot = "c:\temp\"

#$instanceid = 'i-18b32ef3'

function GetLogs ([string]$instanceid)
{
    Write-verbose "GetLogs InstanceId=$instanceid"
    $instance = Get-WinEC2Instance $instanceid *
    if ($instance.State -ne 'stopped')
    {
        $a = Stop-WinEC2Instance  $instanceid
    }

    $volumeid = $instance.Instance.BlockdeviceMappings.Ebs.VolumeId

    Dismount-EC2Volume -InstanceId $instanceid -VolumeId $volumeid
    
    $myinstanceid = (Invoke-WebRequest http://169.254.169.254/latest/meta-data/instance-id).Content

    RetryOnError {Add-EC2Volume -InstanceId $myinstanceid -VolumeId $volumeid -Device '/dev/sda2'} -retryCount 5

    Sleep 10 # Eventual Consistency
    Get-Disk | where { $_.OperationalStatus -eq 'Offline' } | Set-Disk -IsOffline:$false

    $disk = Get-Disk | where { $_.Number -eq 3 }

    $driveLetter = ($disk | Get-Partition).DriveLetter | select -Last 1
    $driveLetter 

    $folder = Join-Path  $dumproot $instanceid
    md $folder -ea 0 > $null
    del "$folder\*" -ea 0 -Force
    md "$folder\install" -ea 0 > $null
    md "$folder\uninstall" -ea 0 > $null
    $folder

    copy "$($driveLetter):\temp\AWSDriverUpgradeLog.txt" $folder
    copy "$($driveLetter):\Windows\System32\config\system" $folder
    copy "$($driveLetter):\Users\Administrator\AppData\Local\Temp\AWS_PV_Drivers*.log" "$folder\uninstall"
    copy "$($driveLetter):\Windows\Temp\AWS_PV_Drivers*.log" "$folder\install"
    
#    start $folder

    $disk | Set-Disk -IsOffline:$true

    Dismount-EC2Volume -InstanceId $myinstanceid -VolumeId $volumeid

    RetryOnError {Add-EC2Volume -InstanceId $instanceid -VolumeId $volumeid -Device '/dev/sda1'} -retryCount 5
}
