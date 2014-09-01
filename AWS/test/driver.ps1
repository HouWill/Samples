# You should define before running this script.
#    $name - You can create some thing like '1', '2', '3' etc for each session
#    $cred - can be initialized with $cred = Get-Credential
#

cls
trap { break } #This stops execution on any exception
$ErrorActionPreference = 'Stop'
Set-DefaultAWSRegion $DefaultRegion

function RunOne ($instancetype)
{
    Write-Host '-----------------------------------------' -ForegroundColor Green
    Write-Host "Creating instance type $startinstancetype" -ForegroundColor Green
    Write-Host '-----------------------------------------' -ForegroundColor Green

    Get-PSSession | Remove-PSSession -ea 0
    try
    {
        Remove-WinEC2Instance $name
    }
    catch
    {
    }
    $null = New-WinEC2Instance -Name $name -InstanceType $instancetype -ImagePrefix 'Windows_Server-2012-R2_RTM-English-64Bit-Base-2014.07.10' -NewPassword 'Secret.'

    $PublicIpAddress = (Get-WinEC2Instance $name).PublicIpAddress

    $cmd = {
        md 'c:\temp' -ea 0 | Out-Null
        cd 'c:\temp'
        del 'c:\temp\*' -Force
        $zipfile = '.\RemediateDriverIssue-7.2.3.1.zip'
        #$downloadurl = 'https://s3-us-west-2.amazonaws.com/mlanner-drivers/RemediateDriverIssue-7.3.2.zip'
        $downloadurl = 'https://s3-us-west-2.amazonaws.com/mlanner-drivers/RemediateDriverIssue-7.2.2.zip'
        Write-Host "Downloading $downloadurl"
        Invoke-WebRequest $downloadurl -OutFile $zipfile | Out-Null
        Write-Host 'download complete...'

        $shell=new-object -com shell.application
        $zipfileitem = Get-Item $zipfile
        $files = $shell.namespace($zipfileitem.FullName).items()
        $shell.namespace((Get-Location).Path).Copyhere($files)
        $shell = $null

        powershell -noprofile -executionpolicy unrestricted -file .\RemediateDriverIssue.ps1

        echo 'Before devices'
        (dir 'HKLM:\SYSTEM\CurrentControlSet\Enum\PCI\VEN_5853&DEV_0001&SUBSYS_00015853&REV_01').pschildname.substring(13)

        echo 'break it!'
        RUNDLL32.exe pnpclean.dll,RunDLL_PnpClean /DEVICES /MAXCLEAN
        Sleep 2
        echo 'After devices'
        (dir 'HKLM:\SYSTEM\CurrentControlSet\Enum\PCI\VEN_5853&DEV_0001&SUBSYS_00015853&REV_01').pschildname.substring(13)
    
        Write-Host 'Going to run remediation'
        powershell -noprofile -executionpolicy unrestricted -file .\RemediateDriverIssue.ps1
        Write-Host 'Complete....'
    }

    $s = Invoke-Command -ComputerName $PublicIpAddress -Credential $cred -ScriptBlock $cmd -InDisconnectedSession
    try
    {
        Receive-PSSession $s
    }
    catch
    {
    }

    for ($i=1; $i -le 3; $i++)
    {
        Write-Host "Reboot #$i" -ForegroundColor Green

        try
        {
            Write-Host "Waiting for ping to fail" -ForegroundColor Green
            $cmd = { ping  $PublicIpAddress; $LASTEXITCODE -ne 0}
            $a = Wait $cmd "#$i of 3 - Waiting for ping to fail" 300
        }
        catch
        {
            Write-Host "ping did not fail, so checking if driver install succeeded" -ForegroundColor Green
            $cmd = { 
                cat C:\temp\AWSDriverUpgradeLog.txt
            }
            $log = Invoke-Command -ComputerName $PublicIpAddress -Credential $cred -ScriptBlock $cmd
            if (($log | Select-String 'verified' | measure -Line).Lines -lt 2)
            {
                throw 'AWSDriver upgrade failed'
            }
        }

        Write-Host "Waiting for ping to succeed" -ForegroundColor Green
        $cmd = { ping  $PublicIpAddress; $LASTEXITCODE -eq 0}
        $a = Wait $cmd "#$i of 3 - Waiting for ping to succeed" 450
    }
    try
    {
        Remove-PSSession $s
    }
    catch 
    {
    }

    Write-Host "Waiting for remote connection" -ForegroundColor Green
    $cmd = {New-PSSession $PublicIpAddress -Credential $Cred -Port 80}
    $s = Wait $cmd "Remote connection" 300
    Remove-PSSession $s
    Write-Host "Remote connection established" -ForegroundColor Green
}

$instancetypes = @('m3.large', 'm1.large', 'c3.large', 'r3.large', 't2.medium')

foreach ($startinstancetype in $instancetypes)
{
    RunOne $startinstancetype

    Write-Host "Loop through different instance types starting from $startinstancetype" -ForegroundColor Green
    $instanceid = (Get-WinEC2Instance $name).InstanceId
    $PublicIpAddress = (Get-WinEC2Instance $name).PublicIpAddress

    $i = 0
    foreach ($instancetype in $instancetypes)
    {
        $i++
        Write-Host "$i - change instance type to $instancetype for id=$instanceid, " -ForegroundColor Green

        Stop-WinEC2Instance $instanceid

        Edit-EC2InstanceAttribute $instanceid -InstanceType $instancetype

        Start-WinEC2Instance $instanceid -Cred $cred
    }

}
