# You should define before running this script.
#    $name - You can create some thing like '1', '2', '3' etc for each session
param ([string]$name)

if ((Get-Host).Name.Contains(' ISE '))
{
    if ($name.Length -eq 0)
    {
        $name = $psise.CurrentPowerShellTab.DisplayName.Replace('PowerShell ','').Replace(' ','')
    }
}
else
{
    if ($name.Length -eq 0)
    {
        throw "The parameter `$name not defined."
    }
    else
    {
        (get-host).ui.RawUI.WindowTitle = $MyInvocation.MyCommand.Name + " $name"
    }
}

. $PSScriptRoot\..\WinEC2.ps1 -Force
Import-Module $PSScriptRoot\test.psm1 -Force

cls
trap { break } #This stops execution on any exception
$ErrorActionPreference = 'Stop'
Set-DefaultAWSRegion $DefaultRegion
cd c:\temp

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
    $instance = Get-WinEC2Instance $tag
    $instance | Add-Member -NotePropertyName 'ImageName' -NotePropertyValue (Get-EC2Image $instance.ImageId).Name
    $instance 

    ping $instace.PublicIPAddress
    ''
    GetString $obj
}

function Cleanup ()
{
    Get-PSSession | Remove-PSSession -ea 0
    IgnoreError {Remove-WinEC2Instance $name *}
}

function CreateInstance ()
{
    $global:instance = RetryOnError {New-WinEC2Instance -Name $obj.Name -InstanceType $obj.InstanceType -ImagePrefix $obj.ImagePrefix -NewPassword $Password -Placement_AvailabilityZone 'us-east-1d'}
    $obj.PublicIpAddress = $instance.PublicIpAddress
    $obj.InstanceId = $instance.Instanceid

    if ($instance.Length -gt 0 -or $obj.InstanceId.split(' ').Length -gt 1)
    {
        throw 'should not happen????'
    }

    $seconds = 600
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
        del 'c:\temp\*' -Force
        cd 'c:\temp'

        $zipfile = '.\driver.zip'

        "Downloading $($using:obj.DownloadUrl)"
        Invoke-WebRequest $using:obj.DownloadUrl -OutFile $zipfile | Out-Null
        'download complete...'
        
        $shell=new-object -com shell.application
        $zipfileitem = Get-Item $zipfile
        $files = $shell.namespace($zipfileitem.FullName).items()
        $shell.namespace((Get-Location).Path).Copyhere($files)
        $shell = $null

        #.\gflags.exe -p /enable AWSDriverUpgrader.exe /full
        #.\gflags.exe -p /enable LatestDriver.exe /full

        #'glfags enabled'
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
    Wait $cmd "Upgrade" 2400

<#
    try
    {
        Wait $cmd "Upgrade" 900
    }
    catch
    {
        Log "Checking for ping.."
        ping $obj.PublicIpAddress > $null
        if ($LASTEXITCODE -eq 0)
        {
            Log "Waiting for more time"
            Wait $cmd "Upgrade" 1000
        }
        else
        {
            Log "Node is not up"
            throw $_.Exception
        }
    }
#>

    IgnoreError { Remove-PSSession $s } # don't close this session, otherwise the setup might be terminated.
}

function CopyLogs ()
{
    $parts = $obj.DownloadUrl.Split('?')[0].Split('\/')
    $downloadfile = $parts[$parts.Length-1].Replace('.zip','')
    $file = "logs\$downloadfile.$($obj.InstanceId).log"
    $cmd = {
        cat c:\temp\*log.txt
    }
    Invoke-Command -ComputerName $obj.PublicIpAddress -Credential $cred -ScriptBlock $cmd -Port 80 > $file
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
}

function ChangeInstanceTypes ()
{
    for($i = 1; $i -le $maxChangeInstanceCount; $i++)
    {
        $instancetype = RandomPick $instancetypes

        Log "$i - change instance type from $($obj.InstanceType) to $instancetype for id=$($obj.InstanceId)"

        Stop-WinEC2Instance $obj.InstanceId

        Edit-EC2InstanceAttribute $obj.InstanceId -InstanceType $instancetype
        Sleep 5 # Possibly there is an eventual consistency issue
        Start-WinEC2Instance $obj.InstanceId -Cred $cred
        $obj.InstanceType = $instancetype
    }
}

function tag ([string]$id)
{
    if ($id.Length -eq 0)
    {
        $id = (Get-WinEC2Instance $name).InstanceId
    }
    $parts = $DownloadUrl.Split('?')[0].Split('\/')
    $nametag = $parts[$parts.Length-1].Replace('.zip','')
    Write-Verbose "Tagged $id with save-$nametag"
    New-EC2Tag -ResourceId $id -Tag @{Key='Name'; Value="save-$nametag"}
}

#$obj = New-Object 'system.collections.generic.dictionary[[string],[object]]'
$DownloadUrl = 'https://s3.amazonaws.com/yishengl/Upgrader7.2.4_v5.zip'
#$DownloadUrl = 'https://instanceupload.s3.amazonaws.com/PNPUTILLogicChange.zip?AWSAccessKeyId=AKIAIT2B3BZ7BA3RR7SQ&Expires=1412648075&Signature=ZJkFm7LE8fR1WDstIoJXBf9GJSI%3D'
$InstanceTypes = @('m3.large', 'm1.large', 't2.medium', 'r3.large', 'c3.large', 'm3.medium', 'm3.xlarge', 'c3.xlarge', 'r3.xlarge')


$maxChangeInstanceCount = 3 # Number of times to change the instance type

$Password = "Secret." # admin password for the instance
$SecurePassword = $Password | ConvertTo-SecureString -AsPlainText -Force 
$cred = New-Object System.Management.Automation.PSCredential -ArgumentList 'administrator', $SecurePassword

#driver7 - sleep 30 sec before & after each step
#driver8 - Includes the security changes from Ethan, and looking for 'AWS ' instead of 'AWS PV'
#driver11 - with gflags
#driver12 - 6:10pm, 22nd with glfags + cleanup before reboot removed.
#13 - 8pm 22nd, Cleanup before reboot and after. Sleep only before install
#14 - 9am 23rd, Cleanup after reboot
#15 - 3pm, 23rd with jonathans pnp cleanup
#16 - 5pm, added chkdsk and sleep of 2 min after install
#Upgrader7.2.4_CleanupBeforeReboot, 9am 24th

#RandomTestLoop -Tests @('Cleanup', 'CreateInstance', 'Download', 'BreakIt', 'Upgrade', 'CopyLogs', 'Reboot', 'ChangeInstanceTypes') `
RandomTestLoop -Tests @('Cleanup', 'CreateInstance', 'Download', 'Upgrade', 'CopyLogs', 'Reboot') `
    -Parameters @{ 
    DownloadUrl = @($DownloadUrl)
    #InstanceType = @('m3.large', 'm1.large', 'c3.large', 'r3.large', 't2.medium')
    InstanceType = $InstanceTypes
    ImagePrefix =  @(
                    'Windows_Server-2012-R2_RTM-English-64Bit-Base-2014.09.10'
                    'Windows_Server-2012-R2_RTM-English-64Bit-Base-2014.08.13',
                    'Windows_Server-2012-R2_RTM-English-64Bit-Base-2014.07.10',
                    'Windows_Server-2012-R2_RTM-English-64Bit-Base-2014.06.12',
                    'Windows_Server-2012-R2_RTM-English-64Bit-Base-2014.05.20'
                    )
    } `
    -OnError 'ginfo' `
    -MaxCount 100

cat "$name.log"