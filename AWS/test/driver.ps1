# You should define before running this script.
#    $name - You can create some thing like '1', '2', '3' etc for each session


cls
trap { break } #This stops execution on any exception
$ErrorActionPreference = 'Stop'
Set-DefaultAWSRegion $DefaultRegion

$logFile = 'c:\temp\driver.log'
$downloadurl = 'https://s3-us-west-2.amazonaws.com/mlanner-drivers/RemediateDriverIssue-7.2.2-fixed.zip'
$instancetypes = @('m3.large', 'm1.large', 'c3.large', 'r3.large', 't2.medium')
$imageprefixes = @(
                    #'Windows_Server-2012-R2_RTM-English-64Bit-Base-2014.08.13',
                    'Windows_Server-2012-R2_RTM-English-64Bit-Base-2014.07.10',
                    'Windows_Server-2012-R2_RTM-English-64Bit-Base-2014.06.12',
                    'Windows_Server-2012-R2_RTM-English-64Bit-Base-2014.05.20'
                    )

$Password = "Secret." # admin password for the instance

$SecurePassword = $Password | ConvertTo-SecureString -AsPlainText -Force 
$cred = New-Object System.Management.Automation.PSCredential -ArgumentList 'administrator', $SecurePassword

function IgnoreError ($scriptBlock)
{
    try
    {
        . $scriptBlock
    }
    catch
    {
    }
}

function RandomPick ([string[]] $list)
{
    $list[(Get-Random $list.Count)]
}

function RetryOnError ($scriptBlock, $retryCount = 3)
{
    for ($i=1; $i -le $retryCount; $i++)
    {
        try
        {
            . $scriptBlock
            break
        }
        catch
        {
            Write-Host "Error: $($_.Exception.Message), RetryCount=$i, ScriptBlock=$scriptBlock" -ForegroundColor Yellow
            if ($i -eq $retryCount)
            {
                throw $_.Execption
            }
            Sleep 10 # wait before retrying
        }
    }
}

function Log ($message)
{
    Write-Host $message -ForegroundColor Yellow
    RetryOnError {$message >> $logFile}
}

function RunOne ($instancetype, $imagePrefix)
{
    try
    {
        Write-Host '-----------------------------------------------------------------------------------------' -ForegroundColor Green
        Write-Host "Creating instance Type=$startinstancetype, Name=$name, ImagePrefix=$ImagePrefix" -ForegroundColor Yellow
        Write-Host '-----------------------------------------------------------------------------------------' -ForegroundColor Green

        Get-PSSession | Remove-PSSession -ea 0
        IgnoreError {Remove-WinEC2Instance $name}

        RetryOnError {$null = New-WinEC2Instance -Name $name -InstanceType $instancetype -ImagePrefix $ImagePrefix -NewPassword $Password}

        $instace = Get-WinEC2Instance $name
        $PublicIpAddress = $instace.PublicIpAddress
        $instanceid = $instace.Instanceid

        $cmd = {
            md 'c:\temp' -ea 0 | Out-Null
            cd 'c:\temp'
            del 'c:\temp\*' -Force
            $zipfile = '.\RemediateDriverIssue-7.2.2.zip'
            #$downloadurl = 'https://s3-us-west-2.amazonaws.com/mlanner-drivers/RemediateDriverIssue-7.3.2.zip'

            Write-Host "Downloading $($using:downloadurl)"
            Invoke-WebRequest $using:downloadurl -OutFile $zipfile | Out-Null
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
    
        IgnoreError { Receive-PSSession $s }

        for ($i=1; $i -le 3; $i++)
        {
            Write-Host "Reboot #$i, i" -ForegroundColor Green

            try
            {
                Write-Host "Waiting for ping to fail" -ForegroundColor Green
                $cmd = { ping  $PublicIpAddress; $LASTEXITCODE -ne 0}
                $a = Wait $cmd "#$i of 3 - Waiting for ping to fail" 450
            }
            catch
            {
                Write-Host "ping did not fail, so checking if driver install succeeded" -ForegroundColor Green
                $cmd = { 
                    cat C:\temp\AWSDriverUpgradeLog.txt
                }
                $output = Invoke-Command -ComputerName $PublicIpAddress -Credential $cred -ScriptBlock $cmd
                if (($output | Select-String 'verified' | measure -Line).Lines -lt 2)
                {
                    throw 'AWSDriver upgrade failed'
                }
            }

            Write-Host "Waiting for ping to succeed" -ForegroundColor Green
            $cmd = { ping  $PublicIpAddress; $LASTEXITCODE -eq 0}
            $a = Wait $cmd "#$i of 3 - Waiting for ping to succeed" 750
        }
        IgnoreError { Remove-PSSession $s }

        Write-Host "Waiting for remote connection" -ForegroundColor Green
        $cmd = {New-PSSession $PublicIpAddress -Credential $Cred -Port 80}
        $s = Wait $cmd "Remote connection" 300
        Remove-PSSession $s
        Write-Host "Remote connection established" -ForegroundColor Green

        Log "SUCCESS: Instanceid=$instanceid, Type=$instancetype, Name=$name, Reboot Number=$i, ImagePrefix=$imagePrefix, Url=$downloadurl" -ForegroundColor Yellow
    }
    catch
    {
        Log "Fail: Message=$($_.Exception.Message), Instanceid=$instanceid, Type=$instancetype, Name=$name, Reboot Number=$i, ImagePrefix=$imagePrefix, Url=$downloadurl" -ForegroundColor Yellow
        throw $_.Exception
    }
}

while ($true)
{
    $imageprefix = RandomPick $imageprefixes
    $startinstancetype = RandomPick $instancetypes

    RunOne $startinstancetype $imageprefix

    Write-Host "Loop through different instance types starting from $startinstancetype" -ForegroundColor Green
    $instace = Get-WinEC2Instance $name
    $PublicIpAddress = $instace.PublicIpAddress
    $instanceid = $instace.Instanceid

    $i = 0
    foreach ($instancetype in $instancetypes)
    {
        $i++
        Write-Host "$i - change instance type to $instancetype for id=$instanceid, " -ForegroundColor Yellow

        Stop-WinEC2Instance $instanceid

        Edit-EC2InstanceAttribute $instanceid -InstanceType $instancetype
        Sleep 5 # Possibly there is an eventual consistency issue
        Start-WinEC2Instance $instanceid -Cred $cred
    }

}
