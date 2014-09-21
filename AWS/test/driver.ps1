# You should define before running this script.
#    $name - You can create some thing like '1', '2', '3' etc for each session

Import-Module $PSScriptRoot\test.psm1 -Force

cls
trap { break } #This stops execution on any exception
$ErrorActionPreference = 'Stop'
Set-DefaultAWSRegion $DefaultRegion

if ($name -eq $null)
{
    throw '$name is not set.'
}
cd c:\temp

function gstat ()
{
    [int]$success = (cat $logStatFile | Select-String 'Success:').Line | wc -l
    [int]$fail = (cat $logStatFile | Select-String 'Fail:').Line | wc -l
    $precent = [decimal]::Round(100*$success/($success+$fail))
    "Statistics: Success=$success, Fail=$fail percent success=$precent"
}

function gfail ()
{
    (cat $logStatFile | Select-String 'Fail:').Line
}

function retreive ([scriptblock]$cmd, [string]$file)
{
    try
    {
        Invoke-WinEC2Command $name $cmd >> $file
        "Retreived $cmd to $file"   
    }
    catch 
    {
        "Error Retreiving $cmd to $file"   
    }
}

function ginfo ([string]$tag = $name)
{
    md $tag -ea 0
    del "$tag\*" -Force -ea 0
    copy "$tag.log" "$tag\test.log"

    $instance = Get-WinEC2Instance $tag
    $instance | Add-Member -NotePropertyName 'ImageName' -NotePropertyValue (Get-EC2Image $instance.ImageId).Name
    $instance > "$tag\info.log"
    GetString $obj >> "$tag\info.log"
    
    $cmd = {
        echo ''
        echo 'Current Devices'
        (dir 'HKLM:\SYSTEM\CurrentControlSet\Enum\PCI\VEN_5853&DEV_0001&SUBSYS_00015853&REV_01').pschildname.substring(13)
    }
    retreive $cmd "$tag\info.log"
    
    $cmd = {cat C:\Users\Administrator\appdata\local\Temp\AWS_PV_Drivers*log}
    retreive $cmd "$tag\AWSDriverUpgradeLog.txt"

    $cmd = {cat c:\temp\AWSDriverUpgradeLog.txt}
    retreive $cmd "$tag\AWSDriverUpgradeLog.txt"

    $cmd = {cat (dir C:\Users\Administrator\appdata\local\temp\*.log -Exclude "*msi*")}
    retreive $cmd "$tag\AWS_PV_Drivers.log"

    $cmd = {cat C:\Users\Administrator\appdata\local\temp\*msi.log}
    retreive $cmd "$tag\AWS_PV_Drivers.msi.log"

    $cmd = {get-eventlog -logname system | fl}
    retreive $cmd "$tag\eventlog.system.log"
}

function Cleanup ()
{
    Get-PSSession | Remove-PSSession -ea 0
    IgnoreError {Remove-WinEC2Instance $name}
}

function CreateInstance ()
{
    $instace = RetryOnError {New-WinEC2Instance -Name $obj.Name -InstanceType $obj.InstanceType -ImagePrefix $obj.ImagePrefix -NewPassword $Password -Placement_AvailabilityZone 'us-east-1d'}
    $obj.PublicIpAddress = $instace.PublicIpAddress
    $obj.Instanceid = $instace.Instanceid

    $seconds = 10
    "Sleeping for $seconds seconds"
    Sleep -Seconds $seconds
}

function Reboot ()
{
    $retrycount = 3
    for ($i=1; $i -le $retrycount; $i++)
    {
        Log "7.2.4 - Reboot"
        Invoke-Command -ComputerName $obj.PublicIpAddress -Credential $cred -ScriptBlock {Restart-Computer -Force}
        Log "7.2.4 - Waiting for ping fail"
        $cmd = { ping  $obj.PublicIpAddress; $LASTEXITCODE -ne 0}

        try
        {
            $a = Wait $cmd "Waiting for ping fail" 150
        }
        catch
        {
            if ($i -eq $retrycount)
            {
                throw $_.Exception
            }
        }
        break
    }

    Log "7.2.4 - Waiting for ping"
    $cmd = { ping  $obj.PublicIpAddress; $LASTEXITCODE -eq 0}
    $a = Wait $cmd "Waiting for ping" 300
}

function Download ()
{
    $cmd = {
        md 'c:\temp' -ea 0 | Out-Null
        cd 'c:\temp'
        del 'c:\temp\*' -Force
        $zipfile = '.\driver.zip'

        "Downloading $($using:obj.DownloadUrl)"
        Invoke-WebRequest $using:obj.DownloadUrl -OutFile $zipfile | Out-Null
        'download complete...'

        $shell=new-object -com shell.application
        $zipfileitem = Get-Item $zipfile
        $files = $shell.namespace($zipfileitem.FullName).items()
        $shell.namespace((Get-Location).Path).Copyhere($files)
        $shell = $null
    }

    Invoke-Command -ComputerName $obj.PublicIpAddress -Credential $cred -ScriptBlock $cmd
}

function Upgrade ()
{
    $cmd = {
        cd 'c:\temp'
        echo 'Before devices'
        (dir 'HKLM:\SYSTEM\CurrentControlSet\Enum\PCI\VEN_5853&DEV_0001&SUBSYS_00015853&REV_01').pschildname.substring(13)

        Log 'Going to run upgrade'
        .\AWSDriverUpgrader.exe /silent
        Log 'complete....'
        Sleep 3
    }

    #Initiate upgrade
    $s = Invoke-Command -ComputerName $obj.PublicIpAddress -Credential $cred -ScriptBlock $cmd -InDisconnectedSession 
    IgnoreError { Receive-PSSession $s }

    #cat C:\temp\AWSDriverUpgradeLog.txt | Select-String 'Install of driver AWS PV Drivers v7.2.4 verified'

    #Wait for upgrade to complete
    $cmdinner = {
        cat C:\temp\AWSDriverUpgradeLog.txt | Select-String 'Upgrade Completed!!!'
    }
    Log "Waiting for upgrade to complete"
    $cmd = {Invoke-Command -ComputerName $obj.PublicIpAddress -Credential $cred -ScriptBlock $cmdinner}
    Wait $cmd "Upgrade" 900

    IgnoreError { Remove-PSSession $s } # don't close this session, otherwise the setup might be terminated.
}

function BreakIt () # simulate the schedule task
{
    $cmd = {
        echo '7.2.4 - Devices list before breaking'
        (dir 'HKLM:\SYSTEM\CurrentControlSet\Enum\PCI\VEN_5853&DEV_0001&SUBSYS_00015853&REV_01').pschildname.substring(13)

        echo 'Break it! (RUNDLL32.exe pnpclean.dll,RunDLL_PnpClean /DEVICES /MAXCLEAN)'
        RUNDLL32.exe pnpclean.dll,RunDLL_PnpClean /DEVICES /MAXCLEAN
        Sleep 2
        echo '7.2.4 - Devices list after breaking'
        (dir 'HKLM:\SYSTEM\CurrentControlSet\Enum\PCI\VEN_5853&DEV_0001&SUBSYS_00015853&REV_01').pschildname.substring(13)
    }
    Invoke-Command -ComputerName $obj.PublicIpAddress -Credential $cred -ScriptBlock $cmd -Port 80
    Reboot
}

function ChangeInstanceTypes ()
{
    for($i = 1; $i -le $maxChangeInstanceCount; $i++)
    {
        $instancetype = RandomPick $instancetypes

        Log "$i - change instance type from $($obj.InstanceType) to $instancetype for id=$($obj.instanceid)"

        Stop-WinEC2Instance $obj.instanceid

        Edit-EC2InstanceAttribute $obj.instanceid -InstanceType $instancetype
        Sleep 5 # Possibly there is an eventual consistency issue
        Start-WinEC2Instance $obj.instanceid -Cred $cred
        $obj.InstanceType = $instancetype
    }
}

#$obj = New-Object 'system.collections.generic.dictionary[[string],[object]]'
$logStatFile = 'c:\temp\driver.log'

$maxChangeInstanceCount = 3 # Number of times to change the instance type
$Password = "Secret." # admin password for the instance

$SecurePassword = $Password | ConvertTo-SecureString -AsPlainText -Force 
$cred = New-Object System.Management.Automation.PSCredential -ArgumentList 'administrator', $SecurePassword
RandomTestLoop -Tests @('Cleanup', 'CreateInstance', 'Download', 'Upgrade', 'Reboot') `
    -Parameters @{ 
    #DownloadUrl = @('https://instanceupload.s3.amazonaws.com/ScheduleTaskLogging.zip?AWSAccessKeyId=AKIAIT2B3BZ7BA3RR7SQ&Expires=1412116181&Signature=F9jHWKiOBcxT1eXhvZndIapD0T4%3D')
    DownloadUrl = @('https://s3.amazonaws.com/sivabuckets3/driver/Driver2.zip')
    InstanceType = @('m3.large', 'm1.large', 'c3.large', 'r3.large', 't2.medium')
    ImagePrefix =  @(
                    'Windows_Server-2012-R2_RTM-English-64Bit-Base-2014.09.10',
                    'Windows_Server-2012-R2_RTM-English-64Bit-Base-2014.08.13',
                    'Windows_Server-2012-R2_RTM-English-64Bit-Base-2014.07.10',
                    'Windows_Server-2012-R2_RTM-English-64Bit-Base-2014.06.12',
                    'Windows_Server-2012-R2_RTM-English-64Bit-Base-2014.05.20'
                    )
    } `
    -OnError 'ginfo' `
    -MaxCount 100

cat "$name.log"