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

$DefaultRegion = 'us-east-1'
$DefaultKeypairFolder = 'c:\temp'

# Lanch EC2 Instance and set the new password
function New-WinEC2Instance
{
    param (
        [string]$InstanceType = 'm3.medium', 
        [string]$ImagePrefix = 'Windows_Server-2012-RTM-English-64Bit-Base',
        [string]$Region = $DefaultRegion,
        [string]$Password = $null,  # if the password is already baked in the image, specify the password
        [string]$NewPassword = $null, # change the passowrd to this new value
        [string]$SecurityGroupName = 'sg_rdp_ps_http_icmp',
        [string]$KeyPairName = 'winec2keypair',
        [string]$ComputerName = $null,
        [string]$PrivateIPAddress = $null
        )

    trap { break } #This stops execution on any exception
    $ErrorActionPreference = 'Stop'
    Set-DefaultAWSRegion $Region
    Write-Verbose ("New-WinEC2Instance InstanceType=$InstanceType, ImagePrefix=$ImagePrefix,Region=$Region," + 
            "SecurityGroupName=$SecurityGroupName, ComputerName=$ComputerName,PrivateIPAddress=$PrivateIPAddress")
    $startTime = Get-Date

    $keyfile = Get-WinEC2KeyFile $KeyPairName
    Write-Verbose "Keyfile=$keyfile"

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
    Set-Item (dir wsman:\localhost\Listener\*\Port -Recurse).pspath 80 -Force
    $(if ($ComputerName -ne $null) {"Rename-Computer -NewName '$ComputerName'`nRestart-Computer" })
    net stop winrm
    net start winrm
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

    $a = New-EC2Instance @parameters
    $instance = $a.Instances[0]
    $instanceid = $instance.InstanceId
    Write-Verbose "instanceid=$instanceid"

    if ($ComputerName)
    {
        New-EC2Tag -ResourceId $instanceid -Tag @{Key='ComputerName'; Value=$ComputerName}
    }

    $cmd = { $(Get-EC2Instance -Filter @{Name = "instance-id"; Values = $instanceid}).Instances[0].State.Name -eq "Running" }
    $a = Wait $cmd "New-WinEC2Instance - Waiting for running state" 450
    $runningTime = Get-Date
        
    #Wait for ping to succeed
    $a = Get-EC2Instance -Filter @{Name = "instance-id"; Values = $instanceid}
    $publicDNS = $a.Instances[0].PublicDnsName

    $cmd = { ping  $publicDNS; $LASTEXITCODE -eq 0}
    $a = Wait $cmd "New-WinEC2Instance - Waiting for ping" 450
    $pingTime = Get-Date

    #Wait until the password is available
    if (-not $Password)
    {
        $cmd = {Get-EC2PasswordData -InstanceId $instanceid -PemFile $keyfile -Decrypt}
        $Password = Wait $cmd "New-WinEC2Instance - Waiting to retreive password" 600
    }

    Write-Verbose "$Password  $publicDNS"

    $securepassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $creds = New-Object System.Management.Automation.PSCredential ("Administrator", $securepassword)
    $passwordTime = Get-Date
    
    $cmd = {New-PSSession $publicDNS -Credential $creds -Port 80}
    $s = Wait $cmd "New-WinEC2Instance - Establishing remote connection" 300

    if ($NewPassword)
    {
        #Change password
        $cmd = { param($password)	
	            $admin=[adsi]("WinNT://$env:computername/administrator, user")
	            $admin.psbase.invoke('SetPassword', $password) }

        Invoke-Command -Session $s $cmd -ArgumentList $NewPassword 2>$null

        Remove-PSSession $s
        $securepassword = ConvertTo-SecureString $NewPassword -AsPlainText -Force
        $creds = New-Object System.Management.Automation.PSCredential ("Administrator", $securepassword)
        $s = New-PSSession $publicDNS -Credential $creds -Port 80 
    }
    Remove-PSSession $s
    $remoteTime = Get-Date

    Write-Verbose ('New-WinEC2Instance - {0:mm}:{0:ss} - to running state' -f ($runningTime - $startTime))
    Write-Verbose ('New-WinEC2Instance - {0:mm}:{0:ss} - to ping to succeed' -f ($pingTime - $startTime))
    Write-Verbose ('New-WinEC2Instance - {0:mm}:{0:ss} - to retreive password' -f ($passwordTime - $startTime))
    Write-Verbose ('New-WinEC2Instance - {0:mm}:{0:ss} - to establish remote connection' -f ($remoteTime - $startTime))
    $instance
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

function findInstance ([Parameter (Position=1, Mandatory=$true)]$computerNameOrInstanceId,
    [string][Parameter(Position=2)]$desiredState = '*'
    )
{
    $instance = $null

    foreach ($tempinstance in (Get-EC2Instance).Instances)
    {
        if ($tempinstance.InstanceId -eq $computerNameOrInstanceId)
        {
            $instance = $tempinstance
            break
        } 
        foreach ($tag in $tempinstance.Tag)
        {
            if ($tag.Key -eq 'ComputerName' -and $tag.Value -eq $computerNameOrInstanceId)
            {
                $instance = $tempinstance
                break
            }
        }
    }
    if ($instance -eq $null)
    {
        throw "$computerNameOrInstanceId is neither an instanceid or found in Tag with key=ComputerName"
    }

    if (-not ($instance.State.Name -like $desiredState))
    {
        throw "Current instance state is $($instance.State.Name), only $desiredState is valid."
    }

    $instance
}

function Stop-WinEC2Instance (
        [Parameter (Position=1, Mandatory=$true)]$ComputerNameOrInstanceId,
        [Parameter(Position=2)]$Region=$DefaultRegion
    )
{
    trap { break }
    $ErrorActionPreference = 'Stop'
    Set-DefaultAWSRegion $Region
    Write-Verbose "Stop-WinEC2Instance - ComputerNameOrInstanceId=$ComputerNameOrInstanceId, Region=$Region"

    $instance = findInstance $ComputerNameOrInstanceId 'running'
    $InstanceId = $instance.InstanceId

    $a = Stop-EC2Instance -Instance $InstanceId -Force

    $cmd = { (Get-EC2Instance -Instance $InstanceId).Instances[0].State.Name -eq "Stopped" }
    $a = Wait $cmd "Stop-WinEC2Instance - Waiting for Stopped state" 450
}


function Start-WinEC2Instance (
        [Parameter (Position=1, Mandatory=$true)]$ComputerNameOrInstanceId,
        [System.Management.Automation.PSCredential][Parameter(Mandatory=$true, Position=2)]$Cred,
        [Parameter(Position=3)]$Region=$DefaultRegion
    )
{
    trap { break }
    $ErrorActionPreference = 'Stop'
    Set-DefaultAWSRegion $Region
    Write-Verbose "Start-WinEC2Instance - ComputerNameOrInstanceId=$ComputerNameOrInstanceId, Region=$Region"
    $startTime = Get-Date

    $instance = findInstance $ComputerNameOrInstanceId 'stopped'
    $InstanceId = $instance.InstanceId
 
    $a = Start-EC2Instance -Instance $InstanceId

    $cmd = { $(Get-EC2Instance -Instance $InstanceId).Instances[0].State.Name -eq "running" }
    $a = Wait $cmd "Start-WinEC2Instance - Waiting for running state" 450

    #Wait for ping to succeed
    $instance = (Get-EC2Instance -Instance $InstanceId).Instances[0]
    $publicDNS = $instance.PublicDnsName

    Write-Verbose "publicDNS = $($instance.PublicDnsName)"

    $cmd = { ping  $publicDNS; $LASTEXITCODE -eq 0}
    $a = Wait $cmd "Start-WinEC2Instance - Waiting for ping" 450

    $cmd = {New-PSSession $publicDNS -Credential $Cred -Port 80}
    $s = Wait $cmd "Start-WinEC2Instance - Establishing remote connection" 300
    Remove-PSSession $s

    Write-Verbose ('Start-WinEC2Instance - {0:mm}:{0:ss} - to start' -f ((Get-Date) - $startTime))
}

function ReStart-WinEC2Instance (
        [Parameter (Position=1, Mandatory=$true)]$ComputerNameOrInstanceId,
        [System.Management.Automation.PSCredential][Parameter(Mandatory=$true, Position=2)]$Cred,
        [Parameter(Position=3)]$Region=$DefaultRegion
    )
{
    trap { break }
    $ErrorActionPreference = 'Stop'
    Set-DefaultAWSRegion $Region
    Write-Verbose "ReStart-WinEC2Instance - ComputerNameOrInstanceId=$ComputerNameOrInstanceId, Region=$Region"

    $startTime = Get-Date
    $instance = findInstance $ComputerNameOrInstanceId 'running'
    $InstanceId = $instance.InstanceId
    $publicDNS = $instance.PublicDnsName
 
    $a = Restart-EC2Instance -Instance $InstanceId

    #Wait for ping to fail
    $cmd = { ping  $publicDNS; $LASTEXITCODE -ne 0}
    $a = Wait $cmd "ReStart-WinEC2Instance - Waiting for ping to fail" 450

    #Wait for ping to succeed
    $cmd = { ping  $publicDNS; $LASTEXITCODE -eq 0}
    $a = Wait $cmd "ReStart-WinEC2Instance - Waiting for ping to succeed" 450

    $cmd = {New-PSSession $publicDNS -Credential $Cred -Port 80}
    $s = Wait $cmd "ReStart-WinEC2Instance - Establishing remote connection" 300
    Remove-PSSession $s

    Write-Verbose ('ReStart-WinEC2Instance - {0:mm}:{0:ss} - to restart' -f ((Get-Date) - $startTime))
}


function Connect-WinEC2Instance (
        [Parameter (Position=1, Mandatory=$true)]$ComputerNameOrInstanceId,
        $Region=$DefaultRegion
    )
{
    trap { break }
    Set-DefaultAWSRegion $Region

    $instance = findInstance $ComputerNameOrInstanceId 'running'
    mstsc /v:$($instance.PublicIpAddress)
}

function Get-WinEC2Instance
{
    param (
        $Region=$DefaultRegion
    )

    $instances = (Get-EC2Instance -Region $Region).Instances

    foreach ($instance in $instances)
    {
       $obj = New-Object PSObject -Property  @{
           InstanceId=$instance.InstanceId
           State = $instance.State.Name
           PublicIpAddress = $instance.PublicIpAddress
           PublicDNS = $instances.PublicDNS
           PrivateIpAddress = $instance.PrivateIpAddress
           NetworkInterfaces = $instance.NetworkInterfaces
           InstanceType = $instance.InstanceType
        }


        foreach ($tag in $instance.Tag)
        {
            $obj | Add-Member -NotePropertyName ('Tag' + $tag.Key) -NotePropertyValue $tag.Value
        }
        $obj
    }
}

function Remove-WinEC2Instance (
        [Parameter (Position=1, Mandatory=$true)]$ComputerNameOrInstanceId,
        [Parameter(Position=2)]$Region=$DefaultRegion
    )
{
    trap { break }
    $ErrorActionPreference = 'Stop'
    Set-DefaultAWSRegion $Region
    Write-Verbose "Remove-WinEC2Instance - ComputerNameOrInstanceId=$ComputerNameOrInstanceId, Region=$Region"

    $instance = findInstance $ComputerNameOrInstanceId '*'

    if ($instance.State.Name -eq 'terminated')
    {
        throw "Remove-WinEC2Instance - ComputerNameOrInstanceId=$ComputerNameOrInstanceId alrady terminated"
    }
    else
    {
        $a = Stop-EC2Instance -Instance $instance.InstanceId -Force -Terminate

        $cmd = { $(Get-EC2Instance -Instance $instance.InstanceId).Instances[0].State.Name -eq 'terminated' }
        $a = Wait $cmd "Remove-WinEC2Instance - Waiting for terminate state" 450
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


# Creates or updates the security group
# Default it enables RDP, PowerShell, HTTP and ICMP.
# Define appropriate switch to disable specific protocol
# If SourceIPRange is not defined, it configures based on http://checkip.amazonaws.com
function Update-WinEC2FireWallSource
{
    param (
        $SecurityGroupName = 'sg_rdp_ps_http_icmp',
        $Region=$DefaultRegion,
        $SourceIPRange = $null,
        [switch] $NoRDP,
        [switch] $NoPS,
        [switch] $NoHTTP,
        [switch] $NoICMP
    )
    trap {break }
    $ErrorActionPreference = 'Stop'

    Set-DefaultAWSRegion $DefaultRegion

    if ($SourceIPRange -eq $null)
    {
        $bytes = (Invoke-WebRequest 'http://checkip.amazonaws.com/').Content
        $SourceIPRange = @([System.Text.Encoding]::Ascii.GetString($bytes).Trim() + "/32")
    }
    else
    {
        $SourceIPRange = @($SourceIPRange) #Make it an array, if not already
    }

    $sg = Get-EC2SecurityGroup | ? { $_.GroupName -eq $SecurityGroupName}
    if ($sg -eq $null)
    {
        #Create the firewall security group
        $groupid = New-EC2SecurityGroup $SecurityGroupName  -Description "Enables rdp, ps, http and icmp"
    }
    else
    {
    
        foreach ($ipPermission in $sg.IpPermissions)
        {
            $delete = $true # will be set to false if we find exact match 

            if ($ipPermission.IpProtocol -eq 'tcp' -and 
                $ipPermission.FromPort -eq 3389 -and $ipPermission.ToPort -eq 3389)
            {
                if (-not $NoRDP)
                {
                    $delete = $false
                    $NoRDP = $true # Already defined don't have to create it again.
                }
            }
            if ($ipPermission.IpProtocol -eq 'tcp' -and 
                $ipPermission.FromPort -eq 5985 -and $ipPermission.ToPort -eq 5985)
            {
                if (-not $NoPS)
                {
                    $delete = $false
                    $NoPS = $true # Already defined don't have to create it again.
                }
            }
            if ($ipPermission.IpProtocol -eq 'tcp' -and 
                $ipPermission.FromPort -eq 80 -and $ipPermission.ToPort -eq 80)
            {
                if (-not $NoHTTP)
                {
                    $delete = $false
                    $NoHTTP = $true # Already defined don't have to create it again.
                }
            }
            if ($ipPermission.IpProtocol -eq 'icmp' -and 
                $ipPermission.FromPort -eq -1 -and $ipPermission.ToPort -eq -1)
            {
                if (-not $NoICMP)
                {
                    $delete = $false
                    $NoICMP = $true # Already defined don't have to create it again.
                }
            }

            $update = $false
            if ($ipPermission.IpRanges.Count -ne $SourceIPRange.Count)
            {
                $update = $true
            }
            else
            {
                foreach ($sourceIP in $SourceIPRange)
                {
                    if (-not $ipPermission.IpRanges.Contains($sourceIP))
                    {
                        $update = $true
                        break
                    }
                }
            }

            if ($delete -or $update)
            {
                Revoke-EC2SecurityGroupIngress -GroupName $SecurityGroupName `
                    -IpPermissions $ipPermission
                if (-not $delete)
                {
                    $ipPermission.IpRanges = $SourceIPRange
                    Grant-EC2SecurityGroupIngress -GroupName $SecurityGroupName `
                        -IpPermissions $ipPermission
                }
            }
        }
    }

    if (-not $NoRDP)
    {
        Grant-EC2SecurityGroupIngress -GroupName $SecurityGroupName -IpPermissions `
          @{IpProtocol = 'tcp'; FromPort = 3389; ToPort = 3389; IpRanges = $SourceIPRange}
    }
    if (-not $NoPS)
    {
        Grant-EC2SecurityGroupIngress -GroupName $SecurityGroupName -IpPermissions `
          @{IpProtocol = 'tcp'; FromPort = 5985; ToPort = 5986; IpRanges = $SourceIPRange}
    }
    if (-not $NoHTTP)
    {
        Grant-EC2SecurityGroupIngress -GroupName $SecurityGroupName -IpPermissions `
          @{IpProtocol = 'tcp'; FromPort = 80; ToPort = 80; IpRanges = $SourceIPRange}
    }
    if (-not $NoICMP)
    {
        Grant-EC2SecurityGroupIngress -GroupName $SecurityGroupName -IpPermissions `
          @{IpProtocol = 'icmp'; FromPort = -1; ToPort = -1; IpRanges = $SourceIPRange}
    }

    Write-Verbose "Updated $SecurityGroupName IpRange to $SourceIPRange"
}

# local variables has _wait_ prefix to avoid potential conflict in ScriptBlock
# Retry the scriptblock $cmd until no error and return true
# non-zero exit value for the process is considered as a failure
function wait ([ScriptBlock] $Cmd, [string] $Message, [int] $RetrySeconds)
{
    $_wait_t1 = Get-Date
    $_wait_timeout = $false
    while ($true)
    {
        try
        {
            $_wait_success = false
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
        Write-Progress -Activity $Message -PercentComplete (100.0*$_wait_seconds/$RetrySeconds) `
            -Status "$_wait_seconds Seconds, will try for $RetrySeconds seconds before timeout"
        Sleep -Seconds 15
    }
    Write-Progress -Activity $Message -Completed
    if ($_wait_timeout)
    {
        Write-Verbose "$_wait_t2 $Message [$([int]($_wait_t2-$_wait_t1).TotalSeconds) Seconds - Timeout]"
        throw "Timeout - $Message"
    }
    else
    {
        Write-Verbose "$_wait_t2 $Message [$([int]($_wait_t2-$_wait_t1).TotalSeconds) Seconds]"
    }
}
