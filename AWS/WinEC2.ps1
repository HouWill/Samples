#--------------------------------------------------------------------------------------------
#   Copyright 2014 Sivaprasad Padisetty
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http:#www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#--------------------------------------------------------------------------------------------


# Pre requisites
#   Signup for AWS and get the AccessKey & SecretKey. http://docs.aws.amazon.com/powershell/latest/userguide/pstools-appendix-signup.html
#   Read the setup instructions http://docs.aws.amazon.com/powershell/latest/userguide/pstools-getting-set-up.html
#   Install PowerShell module from http://aws.amazon.com/powershell/
#
# set the default credentials by calling something below
#   Initialize-AWSDefaults -AccessKey AKIAIOSFODNN7EXAMPLE -SecretKey wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY -Region us-east-1
#
# You need to add either publicDNSName or * to make PS remoting work for non domain machines
#    Make sure you understand the risk before doing this
#    Set-Item WSMan:\localhost\Client\TrustedHosts "*" -Force
#    It is better if you add full DNS name instead of *. Because * will match any machine name
# 
# This script focuses on on basic function, does not include security or error handling.
#
# Since this is focused on basics, it is better to run blocks of code.
#    if you are running blocks of code from ISE PSScriptRoot will not be defined.

#

$VerbosePreference='continue'
$DefaultRegion = 'us-east-1'
$DefaultKeypairFolder = 'c:\temp'
import-module 'C:\Program Files (x86)\AWS Tools\PowerShell\AWSPowerShell\AWSPowerShell.psd1'
# Lanch EC2 Instance and set the new password

function New-WinEC2Instance
{
    param (
        [string]$InstanceType = 't2.medium',
        [string]$ImagePrefix = 'Windows_Server-2012-R2_RTM-English-64Bit-Base',
            #'Windows_Server-2012-R2_RTM-English-64Bit-GP2-', 
            # Windows_Server-2008-R2_SP1-English-64Bit-Base
            # Windows_Server-2012-RTM-English-64Bit-SQL_2012_SP1_Standard
            # Windows_Server-2012-RTM-English-64Bit-Base
        [string]$Region = $DefaultRegion,
        [string]$Password = $null, # if the password is already baked in the image, specify the password
        [string]$NewPassword = $null, # change the passowrd to this new value
        [string]$SecurityGroupName = 'sg_winec2',
        [string]$KeyPairName = 'winec2keypair',
        [string]$Name = $null,
        [switch]$RenameComputer, # if set, will rename computer to match with $Name
        [string]$PrivateIPAddress = $null,
        [int32]$IOPS = 0,
        [string]$volumetype = 'standard',
        [switch]$DontCleanUp, # Don't cleanup EC2 instance on error
        [string]$Placement_AvailabilityZone = $null
        )

    trap { break } #This stops execution on any exception
    $ErrorActionPreference = 'Stop'

    Set-DefaultAWSRegion $Region
    Write-Verbose ("New-WinEC2Instance InstanceType=$InstanceType, ImagePrefix=$ImagePrefix,Region=$Region, " +
            "SecurityGroupName=$SecurityGroupName, Name=$Name,PrivateIPAddress=$PrivateIPAddress, " +
            "IOPS=$IOPS, Placement_AvailabilityZone=$Placement_AvailabilityZone")
    $instanceid = $null

    try
    {
        #Find the Windows Server 2012 imageid
        $a = Get-EC2Image -Filters @{Name = "name"; Values = "$imageprefix*"}
        if ($a -eq $null)
        {
            Write-Error "Image with prefix '$imageprefix' not found"
            return
        }
        $imageid = $a[$a.Length-1].ImageId #get the last one if there are more than one image
        $imagename = $a[$a.Length-1].Name
        Write-Verbose "imageid=$imageid, imagename=$imagename"
        #Launch the instance
        $userdata = @"
<powershell>
Enable-NetFirewallRule FPS-ICMP4-ERQ-In
Set-NetFirewallRule -Name WINRM-HTTP-In-TCP-PUBLIC -RemoteAddress Any
New-NetFirewallRule -Name "WinRM80" -DisplayName "WinRM80" -Protocol TCP -LocalPort 80
Set-Item WSMan:\localhost\Service\EnableCompatibilityHttpListener -Value true
#Set-Item (dir wsman:\localhost\Listener\*\Port -Recurse).pspath 80 -Force
$(if ($Name -eq $null -or (-not $RenameComputer)) { 'Restart-Service winrm' }
  else {"Rename-Computer -NewName '$Name';Restart-Computer" }
)
</powershell>
"@

        $userdataBase64Encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($userdata))
        $parameters = @{
            ImageId = $imageid
            MinCount = 1
            MaxCount = 1
            InstanceType = $InstanceType
            KeyName = $KeyPairName
            SecurityGroupIds = (Get-EC2SecurityGroup -GroupNames $SecurityGroupName).GroupId
            UserData = $userdataBase64Encoded
        }
        if ($Placement_AvailabilityZone)
        {
            $parameters.'Placement_AvailabilityZone' = $Placement_AvailabilityZone
        }
        if ($PrivateIPAddress)
        {
            $parameters.'PrivateIPAddress' = $PrivateIPAddress
            foreach ($subnet in Get-EC2Subnet)
            {
                if (checkSubnet $subnet.CidrBlock $PrivateIPAddress)
                {
                    $parameters.'SubnetId' = $subnet.SubnetId
                    break
                }
            }
            if (-not $parameters.ContainsKey('SubnetId'))
            {
                throw "Matching subnet for $PrivateIPAddress not found"
            }
        }

        $Volume = New-Object Amazon.EC2.Model.EbsBlockDevice
        $Volume.DeleteOnTermination = $True
        
        if ($IOPS -eq 0)
        {
            $Volume.VolumeType = $volumetype
        }
        else
        {
            $Volume.VolumeType = 'io1'
            $volume.IOPS = $IOPS
            $parameters.'EbsOptimized' = $True
        }

        $Mapping = New-Object Amazon.EC2.Model.BlockDeviceMapping
        $Mapping.DeviceName = '/dev/sda1'
        $Mapping.Ebs = $Volume

        $parameters.'BlockDeviceMapping' = $Mapping

        $startTime = Get-Date
        $a = New-EC2Instance @parameters
        $instance = $a.Instances[0]

        #$awscred = (Get-AWSCredentials -StoredCredentials 'AWS PS Default').GetCredentials()
        #$ec2clinet = New-Object Amazon.EC2.AmazonEC2Client($awscred.AccessKey,$awscred.SecretKey,$DefaultRegionEndpoint)
        #$resp = $ec2clinet.RunInstances($parameters)
        #$instance = $resp.RunInstancesResult.Reservation.Instances[0]
        #$ec2clinet = $null

        $instanceid = $instance.InstanceId
        Write-Verbose "instanceid=$instanceid"

        if ($Name)
        {
            New-EC2Tag -ResourceId $instanceid -Tag @{Key='Name'; Value=$Name}
        }

        $cmd = { $(Get-EC2Instance -Filter @{Name = "instance-id"; Values = $instanceid}).Instances[0].State.Name -eq "Running" }
        $a = Wait $cmd "New-WinEC2Instance - running state" 450
        $runningTime = Get-Date
        
        #Wait for ping to succeed
        $a = Get-EC2Instance -Filter @{Name = "instance-id"; Values = $instanceid}
        $publicDNS = $a.Instances[0].PublicDnsName

        $cmd = { ping $publicDNS; $LASTEXITCODE -eq 0}
        $a = Wait $cmd "New-WinEC2Instance - ping" 600
        $pingTime = Get-Date

        #Wait until the password is available
        if (-not $Password)
        {
            $keyfile = Get-WinEC2KeyFile $KeyPairName
            $cmd = {Get-EC2PasswordData -InstanceId $instanceid -PemFile $keyfile -Decrypt}
            $Password = Wait $cmd "New-WinEC2Instance - retreive password" 600
        }

        Write-Verbose "$Password $publicDNS"

        $securepassword = ConvertTo-SecureString $Password -AsPlainText -Force
        $creds = New-Object System.Management.Automation.PSCredential ("Administrator", $securepassword)
        $passwordTime = Get-Date
    
        $cmd = {New-PSSession $publicDNS -Credential $creds -Port 80}
        $s = Wait $cmd "New-WinEC2Instance - remote connection" 600

        if ($NewPassword)
        {
            #Change password
            $cmd = { param($password)	
                        $admin=[adsi]("WinNT://$env:computername/administrator, user")
                        $admin.psbase.invoke('SetPassword', $password) }
        
            try
            {
                Invoke-Command -Session $s $cmd -ArgumentList $NewPassword 2>$null
            }
            catch # sometime it gives access denied error. ok to mask this error, the next connect will fail if there is an issue.
            {
            }
            Write-Verbose 'Completed setting the new password.'
            Remove-PSSession $s
            $securepassword = ConvertTo-SecureString $NewPassword -AsPlainText -Force
            $creds = New-Object System.Management.Automation.PSCredential ("Administrator", $securepassword)
            $s = New-PSSession $publicDNS -Credential $creds -Port 80
            Write-Verbose 'Test connection established using new password.'
        }
        Remove-PSSession $s
        $remoteTime = Get-Date

        $wininstancce = Get-WinEC2Instance $instanceid
        $time = @{
            Running = $runningTime - $startTime
            Ping = $pingTime - $startTime
            Password = $passwordTime - $startTime
            Remote = $remoteTime - $startTime
        }
        Write-Verbose ('New-WinEC2Instance - {0:mm}:{0:ss} - to running state' -f ($time.Running))
        Write-Verbose ('New-WinEC2Instance - {0:mm}:{0:ss} - to ping to succeed' -f ($time.Ping))
        Write-Verbose ('New-WinEC2Instance - {0:mm}:{0:ss} - to retreive password' -f ($time.Password))
        Write-Verbose ('New-WinEC2Instance - {0:mm}:{0:ss} - to establish remote connection' -f ($time.Remote))

        $wininstancce | Add-Member -NotePropertyName 'Time' -NotePropertyValue $time
        $wininstancce
    }
    catch
    {
        if ($instanceid -ne $null -and (-not $DontCleanUp))
        {
            Stop-EC2Instance -Instance $instanceid -Force -Terminate
        }
        throw $_.Exception
    }
}


function checkSubnet ([string]$cidr, [string]$ip)
{
    $network, [int]$subnetlen = $cidr.Split('/')
    $a = [uint32[]]$network.split('.')
    [uint32] $unetwork = ($a[0] -shl 24) + ($a[1] -shl 16) + ($a[2] -shl 8) + $a[3]
    $mask = (-bnot [uint32]0) -shl (32 - $subnetlen)

    $a = [uint32[]]$ip.split('.')
    [uint32] $uip = ($a[0] -shl 24) + ($a[1] -shl 16) + ($a[2] -shl 8) + $a[3]

    $unetwork -eq ($mask -band $uip)
}

#desired state can be *, or specific names like running or !running
function findInstance (
    [Parameter (Position=1)][string]$nameOrInstanceIds = '*',
    [string][Parameter(Position=2)]$desiredState = '*'
    )
{
    if ($nameOrInstanceIds -eq '*')
    {
        [string[]]$nameOrInstanceIds = @()
    }
    else
    {
        [string[]]$nameOrInstanceIds = $nameOrInstanceIds.Split(',')
    }
    $instances = @()
    $notfilter = $false
    $allfilter = $false
    if ($desiredState -eq '*')
    {
        $allfilter = $true
    }
    elseif ($desiredState[0] -eq '!')
    {
        $notfilter = $true
        $desiredState = $desiredState.Substring(1)
    }

    foreach ($tempinstance in (Get-EC2Instance).Instances)
    {
        if ($allfilter -or
            ($notfilter -and $tempinstance.State.Name -ne $desiredState) -or
            (-not $notfilter -and $tempinstance.State.Name -eq $desiredState))
        {
            if ($nameOrInstanceIds.Count -eq 0 -or $nameOrInstanceIds.Contains($tempinstance.InstanceId))
            {
                $instances += $tempinstance
            }
            else
            {
                foreach ($tag in $tempinstance.Tag)
                {
                    if ($tag.Key -eq 'Name' -and $nameOrInstanceIds.Contains($tag.Value))
                    {
                        $instances += $tempinstance
                    }
                }
            }
        }
    }
    if ($instances.Count -eq 0 -and $nameOrInstanceIds -ne '*')
    {
        throw "$nameOrInstanceIds is neither an instanceid or found in Tag with key=Name with state=$desiredState"
    }
    elseif ($instances.Count -eq 1)
    {
        $instances[0]
    }
    else
    {
        $instances
    }
}

function Get-WinEC2Password (
        [Parameter (Position=1)]$NameOrInstanceId = '*',
        [Parameter(Position=2)][string]$Region=$DefaultRegion
    )
{
    trap { break }
    $ErrorActionPreference = 'Stop'
    Set-DefaultAWSRegion $Region
    Write-Verbose "Get-WinEC2Password - NameOrInstanceId=$NameOrInstanceId, Region=$Region"

    $instances = findInstance $NameOrInstanceId -desiredState 'running'
    foreach ($instance in $instances)
    {
        $wininstance = getWinInstanceFromEC2Instance $instance
        $password = Get-EC2PasswordData -InstanceId $instance.InstanceId -PemFile (Get-WinEC2KeyFile $instance.KeyName) -Decrypt
        if ($wininstance.TagName -ne $null)
        {
            $name = ", name=$($wininstance.TagName)"
        }
        "$($wininstance.InstanceId)$name, Password=$password, IP=$($wininstance.PublicIPAddress)"
    }
}

function Invoke-WinEC2Command (
        [Parameter (Position=1, Mandatory=$true)][string]$NameOrInstanceIds,
        [Parameter(Position=2, Mandatory=$true)][ScriptBlock]$sb,
        [Parameter(Position=3)][PSCredential]$credential=$cred,
        [Parameter(Position=4)][string]$Region=$DefaultRegion
    )
{
    trap { break }
    $ErrorActionPreference = 'Stop'
    Set-DefaultAWSRegion $Region
    Write-Verbose "Invoke-WinEC2Command - NameOrInstanceIds=$NameOrInstanceIds, ScriptBlock=$sb, Region=$Region"

    $instances = findInstance $NameOrInstanceIds 'running'
    foreach ($instance in $instances)
    {
        Invoke-Command -ComputerName $instance.PublicIpAddress -Port 80 -Credential $credential -ScriptBlock $sb
    }
}



function Stop-WinEC2Instance (
        [Parameter (Position=1, Mandatory=$true)][string]$NameOrInstanceIds,
        [Parameter(Position=2)][string]$Region=$DefaultRegion
    )
{
    trap { break }
    $ErrorActionPreference = 'Stop'
    Set-DefaultAWSRegion $Region
    Write-Verbose "Stop-WinEC2Instance - NameOrInstanceIds=$NameOrInstanceIds, Region=$Region"

    $instances = findInstance $NameOrInstanceIds 'running'
    foreach ($instance in $instances)
    {
        $InstanceId = $instance.InstanceId

        $a = Stop-EC2Instance -Instance $InstanceId -Force

        $cmd = { (Get-EC2Instance -Instance $InstanceId).Instances[0].State.Name -eq "Stopped" }
        $a = Wait $cmd "Stop-WinEC2Instance InstanceId=$InstanceId- Stopped state" 450
    }
}


function Start-WinEC2Instance (
        [Parameter (Position=1, Mandatory=$true)]$NameOrInstanceIds,
        [System.Management.Automation.PSCredential][Parameter(Mandatory=$true, Position=2)]$Cred,
        [switch]$IsReachabilityCheck,
        [Parameter(Position=3)]$Region=$DefaultRegion
    )
{
    trap { break }
    $ErrorActionPreference = 'Stop'
    Set-DefaultAWSRegion $Region
    Write-Verbose "Start-WinEC2Instance - NameOrInstanceId=$NameOrInstanceIds, Region=$Region"

    $instances = findInstance $NameOrInstanceIds 'stopped'

    foreach ($instance in $instances)
    {
        $startTime = Get-Date

        $InstanceId = $instance.InstanceId
 
        $a = Start-EC2Instance -Instance $InstanceId

        $cmd = { $(Get-EC2Instance -Instance $InstanceId).Instances[0].State.Name -eq "running" }
        $a = Wait $cmd "Start-WinEC2Instance - running state" 450

        #Wait for ping to succeed
        $instance = (Get-EC2Instance -Instance $InstanceId).Instances[0]
        $publicDNS = $instance.PublicDnsName

        Write-Verbose "publicDNS = $($instance.PublicDnsName)"

        $cmd = { ping  $publicDNS; $LASTEXITCODE -eq 0}
        $a = Wait $cmd "Start-WinEC2Instance - ping" 450

        $cmd = {New-PSSession $publicDNS -Credential $Cred -Port 80}
        $s = Wait $cmd "Start-WinEC2Instance - Remote connection" 300
        Remove-PSSession $s

        if ($IsReachabilityCheck)
        {
            $cmd = { $(Get-EC2InstanceStatus $InstanceId).Status.Status -eq 'ok'}
            $a = Wait $cmd "Start-WinEC2Instance - Reachabilitycheck" 600
        }

        Write-Verbose ('Start-WinEC2Instance - {0:mm}:{0:ss} - to start' -f ((Get-Date) - $startTime))
    }
}

function ReStart-WinEC2Instance (
        [Parameter (Position=1, Mandatory=$true)]$NameOrInstanceIds,
        [System.Management.Automation.PSCredential][Parameter(Mandatory=$true, Position=2)]$Cred,
        [Parameter(Position=3)]$Region=$DefaultRegion
    )
{
    trap { break }
    $ErrorActionPreference = 'Stop'
    Set-DefaultAWSRegion $Region
    Write-Verbose "ReStart-WinEC2Instance - NameOrInstanceId=$NameOrInstanceIds, Region=$Region"

    $instances = findInstance $NameOrInstanceIds 'running'

    foreach ($instance in $instances)
    {
        $startTime = Get-Date
        $InstanceId = $instance.InstanceId
        $publicDNS = $instance.PublicDnsName
 
        $a = Restart-EC2Instance -Instance $InstanceId

        #Wait for ping to fail
        $cmd = { ping  $publicDNS; $LASTEXITCODE -ne 0}
        $a = Wait $cmd "ReStart-WinEC2Instance - ping to fail" 450

        #Wait for ping to succeed
        $cmd = { ping  $publicDNS; $LASTEXITCODE -eq 0}
        $a = Wait $cmd "ReStart-WinEC2Instance - ping to succeed" 450

        $cmd = {New-PSSession $publicDNS -Credential $Cred -Port 80}
        $s = Wait $cmd "ReStart-WinEC2Instance - Remote connection" 300
        Remove-PSSession $s

        $cmd = { $(Get-EC2InstanceStatus $InstanceId).Status.Status -eq 'ok'}
        $a = Wait $cmd "Start-WinEC2Instance - Reachabilitycheck" 600

        Write-Verbose ('ReStart-WinEC2Instance - {0:mm}:{0:ss} - to restart' -f ((Get-Date) - $startTime))
    }
}


function Connect-WinEC2Instance (
        [Parameter (Position=1, Mandatory=$true)]$NameOrInstanceId,
        $Region=$DefaultRegion
    )
{
    trap { break }
    Set-DefaultAWSRegion $Region

    $instance = findInstance $NameOrInstanceId 'running'
    mstsc /v:$($instance.PublicIpAddress)
}

function getWinInstanceFromEC2Instance ($instance)
{
    $obj = New-Object PSObject 
    $obj | Add-Member -NotePropertyName 'InstanceId' -NotePropertyValue $instance.InstanceId
    $obj | Add-Member -NotePropertyName 'State' -NotePropertyValue $instance.State.Name
    $obj | Add-Member -NotePropertyName 'PublicIpAddress' -NotePropertyValue $instance.PublicIpAddress
    $obj | Add-Member -NotePropertyName 'PublicDNSName' -NotePropertyValue $instance.PublicDNSName
    $obj | Add-Member -NotePropertyName 'PrivateIpAddress' -NotePropertyValue $instance.PrivateIpAddress
    $obj | Add-Member -NotePropertyName 'NetworkInterfaces' -NotePropertyValue $instance.NetworkInterfaces
    $obj | Add-Member -NotePropertyName 'InstanceType' -NotePropertyValue $instance.InstanceType
    $obj | Add-Member -NotePropertyName 'KeyName' -NotePropertyValue $instance.KeyName
    $obj | Add-Member -NotePropertyName 'ImageId' -NotePropertyValue $instance.ImageId
    $obj | Add-Member -NotePropertyName 'Instance' -NotePropertyValue $instance

    foreach ($tag in $instance.Tag)
    {
        $obj | Add-Member -NotePropertyName ('Tag' + $tag.Key) -NotePropertyValue $tag.Value
    }

    $obj
}

function Get-WinEC2Instance
{
    param (
        [Parameter (Position=1)][string]$NameOrInstanceIds = '*',
        [Parameter(Position=2)][string]$DesiredState = 'running',
        [Parameter(Position=3)][string]$Region=$DefaultRegion
    )

    Set-DefaultAWSRegion $Region
    $instances = findInstance -nameOrInstanceIds $NameOrInstanceIds -desiredState $DesiredState
    foreach ($instance in $instances)
    {
        getWinInstanceFromEC2Instance $instance
    }
}

function Remove-WinEC2Instance (
        [Parameter (Position=1, Mandatory=$true)][string]$NameOrInstanceIds,
        [Parameter(Position=2)][string]$DesiredState = 'running',
        [Parameter(Position=3)][string]$Region=$DefaultRegion
    )
{
    trap { break }
    $ErrorActionPreference = 'Stop'
    Set-DefaultAWSRegion $Region
    Write-Verbose "Remove-WinEC2Instance - NameOrInstanceIds=$NameOrInstanceIds, Region=$Region"

    $instances = findInstance -nameOrInstanceIds $NameOrInstanceIds -desiredState $DesiredState 
    foreach ($instance in $instances)
    {
        $a = Stop-EC2Instance -Instance $instance.InstanceId -Force -Terminate

        $cmd = { $(Get-EC2Instance -Instance $instance.InstanceId).Instances[0].State.Name -eq 'terminated' }
        $a = Wait $cmd "Remove-WinEC2Instance NameOrInstanceId=$($instance.InstanceId) - terminate state" 1500
    }
}

function New-WinEC2KeyPair (
        [Parameter (Position=1)]$KeyPairName = 'winec2keypair',
        [Parameter(Position=2)]$Region=$DefaultRegion
    )
{
    trap { break }
    $ErrorActionPreference = 'Stop'
    Set-DefaultAWSRegion $Region
    $keyfile = "$DefaultKeypairFolder\$Region.$KeyPairName.pem"
    Write-Verbose "New-WinEC2KeyPair - Keyfile=$keyfile"

    if (Test-Path $keyfile -PathType Leaf)
    {
        throw "New-WinEC2KeyPair - $keyfile already exists"
    }

    $keypair= New-EC2KeyPair -KeyName $KeyPairName
    "$($keypair.KeyMaterial)" | out-file -encoding ascii -filepath $keyfile
    "KeyName: $($keypair.KeyName)" | out-file -encoding ascii -filepath $keyfile -Append
    "KeyFingerprint: $($keypair.KeyFingerprint)" | out-file -encoding ascii -filepath $keyfile -Append
}

function Remove-WinEC2KeyPair (
        [string][Parameter (Position=1)]$KeyPairName = 'winec2keypair',
        [string]$Region=$DefaultRegion
    )
{
    trap { break }
    $ErrorActionPreference = 'Stop'
    Set-DefaultAWSRegion $Region
    $keyfile = "$DefaultKeypairFolder\$Region.$KeyPairName.pem"
    Write-Verbose "Remove-WinEC2KeyPair - Keyfile=$keyfile"

    if (Test-Path $keyfile -PathType Leaf)
    {
        Remove-Item $keyfile -Force
    }

    if (Get-EC2KeyPair -KeyNames $KeyPairName)
    {
        Remove-EC2KeyPair -KeyName $KeyPairName -Force
    }
}

function Get-WinEC2KeyFile (
        [string][Parameter (Position=1)]$KeyPairName = 'winec2keypair',
        [string]$Region=$DefaultRegion
    )
{
    trap { break }
    Set-DefaultAWSRegion $Region
    $keyfile = "$DefaultKeypairFolder\$Region.$KeyPairName.pem"
    Write-Verbose "Test-WinEC2KeyPair - Keyfile=$keyfile"

    if (-not (Test-Path $keyfile -PathType Leaf))
    {
        throw "Test-WinEC2KeyPair - Keyfile=$keyfile Not Found"
    }

    if (-not (Get-EC2KeyPair -KeyNames $KeyPairName))
    {
        $keyfile = $null
        throw "Test-WinEC2KeyPair - KeyPair with name=$KeyPairName not found in Region=$Region"
    }

    $keyfile
}

function Confirm-WinEC2KeyPairAllRegion
{
    $keys = @{}
    $regions = Get-AWSRegion
    foreach ($region in $regions)
    {
        if ($region.Region -eq 'cn-north-1')
        {
            continue;
        }

        foreach ($keypair in Get-EC2KeyPair -Region $Region.Region)
        {
            $keys.Add("$($Region.Region).$($keypair.KeyName)", $keypair)
        }
    }

    $files = @{}
    foreach ($file in Get-ChildItem $DefaultKeypairFolder\*.pem)
    {
        if ($keys.ContainsKey($file.BaseName))
        {
            $keys.Remove($file.BaseName)
        }
        else
        {
            $files.Add($file.BaseName, $file)
        }
    }
    $files
    $keys
}


function Remove-WinEC2InstanceAllRegion
{
    $regions = Get-AWSRegion
    foreach ($region in $regions)
    {
        if ($region.Region -eq 'cn-north-1')
        {
            continue;
        }
        Write-Verbose "Terminating running EC2 Instance form $($region.Region)"
 
        foreach ($instance in (Get-EC2Instance -Region $Region.Region).Instances)
        {
            if ($instance.State.Name -eq 'running')
            {
                Write-Verbose "Terminating InstanceId=$($instance.instanceid)"
                $a = Stop-EC2Instance -Instance $instance.InstanceId -Region $Region.Region -Force -Terminate
            }
        }
    }
}


function Remove-WinEC2KeyPairAllRegion
{
    $regions = Get-AWSRegion
    foreach ($region in $regions)
    {
        if ($wegion.Region -eq 'cn-north-1')
        {
            continue;
        }
        Write-Verbose "Deleting keypair from $($region.Region)"
        foreach ($keypair in (Get-EC2KeyPair -Region $Region.Region))
        {
            Write-Verbose "Remove KeyPair KeyName=$($keypair.KeyName)"
            Remove-EC2KeyPair $keypair.KeyName -Region $Region.Region  -Force
        }
    }
}

function Cleanup-WinEC2
{
    Remove-WinEC2InstanceAllRegion
    Remove-WinEC2KeyPairAllRegion
}

function Update-WinEC2FireWallSource
{
    param (
        $SecurityGroupName = 'sg_winec2',
        $Region=$DefaultRegion,
        $VpcId,
        [Amazon.EC2.Model.IpPermission[]] $IpCustomPermissions
    )
    trap {break }
    $ErrorActionPreference = 'Stop'
    Set-DefaultAWSRegion $Region

    if ($VpcId -eq $null)
    {
        $VpcId  = (Get-EC2Vpc | ? {$_.IsDefault}).VpcId    
    }

    if ($IpCustomPermissions.Length -eq 0)
    {
        $bytes = (Invoke-WebRequest 'http://checkip.amazonaws.com/').Content
        $SourceIPRange = @(([System.Text.Encoding]::Ascii.GetString($bytes).Trim() + "/32"))
        Write-Verbose "$sourceIPRange retreived from checkip.amazonaws.com"

        $IpCustomPermissions = @(
            @{IpProtocol = 'tcp'; FromPort = 3389; ToPort = 3389; IpRanges = $SourceIPRange},
            @{IpProtocol = 'tcp'; FromPort = 5985; ToPort = 5986; IpRanges = $SourceIPRange},
            @{IpProtocol = 'tcp'; FromPort = 80; ToPort = 80; IpRanges = $SourceIPRange},
            @{IpProtocol = 'icmp'; FromPort = -1; ToPort = -1; IpRanges = $SourceIPRange}
        )

        if ($VpcId)
        {
            $CIDRs = (Get-EC2Subnet -Filters @{Name='vpc-id'; value=$VpcId}).CidrBlock
            if ($CIDRs)
            {
                $IpCustomPermissions += @{IpProtocol = -1; FromPort = 0; ToPort = 0; IpRanges = @($CIDRs)}
            }
        }
    }

    $sg = Get-EC2SecurityGroup | ? { $_.GroupName -eq $SecurityGroupName}
    if ($sg -eq $null)
    {
        #Create the firewall security group
        $null = New-EC2SecurityGroup $SecurityGroupName  -Description "WinEC2"
    }
    
    foreach ($ipPermission in $sg.IpPermissions)
    {
        $found = $false
        for ($i = 0; $i -lt $IpCustomPermissions.Length; $i++)
        {
            $ipCustomPermission = $IpCustomPermissions[$i]
            if ($ipPermission.IpProtocol -eq $ipCustomPermission.IpProtocol -and 
                $ipPermission.FromPort -eq $ipCustomPermission.FromPort -and 
                $ipPermission.ToPort -eq $ipCustomPermission.ToPort)
            {
                $match = $true
                if ($ipPermission.IpRanges.Count -eq $ipCustomPermission.IpRanges.Count)
                {
                    foreach ($ipRange in $ipCustomPermission.IpRanges)
                    {
                        if (-not $ipPermission.IpRanges.Contains($ipRange))
                        {
                            $match = $false
                            break
                        }
                    }
                }
                if ($match)
                {
                    $IpCustomPermissions[$i] = $null
                    $found = $true
                    break
                }
            }
        }
        if ($found)
        {
            Write-Verbose ('Update-WinEC2FireWallSource - Skipped Protocol=' + $ipPermission.IpProtocol + `
                            ', FromPort=' + $ipPermission.FromPort + ', ToPort=' + $ipPermission.ToPort + `
                            ', IpRanges=' + $ipPermission.IpRanges)

        }
        else
        {
            Revoke-EC2SecurityGroupIngress -GroupName $SecurityGroupName `
                -IpPermissions $ipPermission
            Write-Verbose ('Update-WinEC2FireWallSource - Revoked Protocol=' + $ipPermission.IpProtocol + `
                            ', FromPort=' + $ipPermission.FromPort + ', ToPort=' + $ipPermission.ToPort + `
                            ', IpRanges=' + $ipPermission.IpRanges)
        }
    }
    foreach ($IpCustomPermission in $IpCustomPermissions)
    {
        if ($IpCustomPermission)
        {
            Grant-EC2SecurityGroupIngress -GroupName $SecurityGroupName `
                -IpPermissions $IpCustomPermission
            Write-Verbose ('Update-WinEC2FireWallSource - Granted Protocol=' + $IpCustomPermission.IpProtocol + `
                            ', FromPort=' + $IpCustomPermission.FromPort + ', ToPort=' + $IpCustomPermission.ToPort + `
                            ', IpRanges=' + $IpCustomPermission.IpRanges)
        }
    }

    Write-Verbose "Update-WinEC2FireWallSource - Updated $SecurityGroupName"
}

# local variables has _wait_ prefix to avoid potential conflict in ScriptBlock
# Retry the scriptblock $cmd until no error and return true
function wait ([ScriptBlock] $Cmd, [string] $Message, [int] $RetrySeconds)
{
    $_wait_activity = "Waiting for $Message to succeed"
    $_wait_t1 = Get-Date
    $_wait_timeout = $false
    while ($true)
    {
        try
        {
            $_wait_success = $false
            $_wait_result = & $cmd 2>$null | select -Last 1 
            if ($? -and $_wait_result)
            {
                $_wait_success = $true
            }
        }
        catch
        {
        }
        $_wait_t2 = Get-Date
        if ($_wait_success)
        {
            $_wait_result
            break;
        }
        if (($_wait_t2 - $_wait_t1).TotalSeconds -gt $RetrySeconds)
        {
            $_wait_timeout = $true
            break
        }
        $_wait_seconds = [int]($_wait_t2 - $_wait_t1).TotalSeconds
        Write-Progress -Activity $_wait_activity `
            -PercentComplete (100.0*$_wait_seconds/$RetrySeconds) `
            -Status "$_wait_seconds Seconds, will try for $RetrySeconds seconds before timeout, Current result=$_wait_result"
        Sleep -Seconds 5
    }
    Write-Progress -Activity $_wait_activity -Completed
    if ($_wait_timeout)
    {
        Write-Verbose "$_wait_t2 $Message [$([int]($_wait_t2-$_wait_t1).TotalSeconds) Seconds - Timeout], Current result=$_wait_result"
        throw "Timeout - $Message after $RetrySeconds seconds, Current result=$_wait_result"
    }
    else
    {
        Write-Verbose "$_wait_t2 Succeeded $Message in $([int]($_wait_t2-$_wait_t1).TotalSeconds) Seconds."
    }
}

New-Alias cwin Connect-WinEC2Instance
New-Alias nwin New-WinEC2Instance
New-Alias rwin Remove-WinEC2Instance
New-Alias icmwin Invoke-WinEC2Command
