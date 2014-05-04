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

$defaultRegion = 'us-west-1'

# Lanch EC2 Instance and set the new password
function New-WinEC2Instance
{
    param (
        $InstanceType = 'm3.medium', 
        $ImagePrefix = 'Windows_Server-2012-RTM-English-64Bit-Base',
        $Region=$defaultRegion,
        $Password = $null,  # if the password is already baked in the image, specify the password
        $NewPassword = $null, # change the passowrd to this new value
        $SecurityGroupName = 'sg_rdp_ps_http_icmp',
        $ComputerName = $null,
        $PrivateIPAddress = $null
        )

    trap { break } #This stops execution on any exception

    Set-DefaultAWSRegion $Region

    Update-WinEC2FireWallSource -SecurityGroupName $SecurityGroupName

    $startTime = Get-Date

    #create a KeyPair, this is used to encrypt the Administrator password.
    if (Get-EC2KeyPair -Filters @{Name = "key-name"; Values = "keypair1"})
    {
        Write-Error 'keypair1 is already present' 
        return
    }

    #Find the Windows Server 2012 imageid
    $a = Get-EC2Image -Filters @{Name = "name"; Values = "$imageprefix*"}
    if ($a -eq $null)
    {
        Write-Error "Image with prefix '$imageprefix' not found"
        return
    }
    $imageid = $a[$a.Length-1].ImageId #get the last one if there are more than one image
    $imagename = $a[$a.Length-1].Name
    Write-Host "imageid=$imageid, imagename=$imagename"

    #Create keypair
    $keyfile = [System.IO.Path]::GetTempFileName()
    Write-Host "Keyfile=$keyfile"
    $keypair1 = New-EC2KeyPair -KeyName keypair1
    "$($keypair1.KeyMaterial)" | out-file -encoding ascii -filepath $keyfile
    "KeyName: $($keypair1.KeyName)" | out-file -encoding ascii -filepath $keyfile -Append
    "KeyFingerprint: $($keypair1.KeyFingerprint)" | out-file -encoding ascii -filepath $keyfile -Append

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
        KeyName = 'keypair1'
        SecurityGroups = $SecurityGroupName
        UserData = $userdataBase64Encoded
    }
    $(if ($PrivateIPAddress){ $parameters.'PrivateIPAddress' = $PrivateIPAddress})

    $a = New-EC2Instance @parameters
    $instance = $a.Instances[0]
    $instanceid = $instance.InstanceId
    Write-Host "instanceid=$instanceid"

    if ($ComputerName)
    {
        New-EC2Tag -ResourceId $instanceid -Tag @{Key='ComputerName'; Value=$ComputerName}
    }

    $cmd = { $(Get-EC2Instance -Filter @{Name = "instance-id"; Values = $instanceid}).Instances[0].State.Name -eq "Running" }
    $a = Wait $cmd "Waiting for running state" 450
    $runningTime = Get-Date
        
    #Wait for ping to succeed
    $a = Get-EC2Instance -Filter @{Name = "instance-id"; Values = $instanceid}
    $publicDNS = $a.Instances[0].PublicDnsName

    $cmd = { echo "publicDNS=$publicDNS"; ping  $publicDNS}
    $a = Wait $cmd "Waiting for ping" 450
    $pingTime = Get-Date

    #Wait until the password is available
    if ($Password -eq $null)
    {
        $cmd = {Get-EC2PasswordData -InstanceId $instanceid -PemFile $keyfile -Decrypt}
        $Password = Wait $cmd "Waiting to retreive password" 600
    }

    #Password is received, delete keypair
    Remove-EC2KeyPair -KeyName keypair1 -Force
    Remove-Item $keyfile
    "$Password  $publicDNS"

    $securepassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $creds = New-Object System.Management.Automation.PSCredential ("Administrator", $securepassword)
    $passwordTime = Get-Date
    
    $cmd = {New-PSSession $publicDNS -Credential $creds -Port 80}
    $s = Wait $cmd "Establishing remote connection" 300

    if ($newpassword -ne $null)
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

    Write-Host ('{0:mm}:{0:ss} - to running state' -f ($runningTime - $startTime))
    Write-Host ('{0:mm}:{0:ss} - to ping to succeed' -f ($pingTime - $startTime))
    Write-Host ('{0:mm}:{0:ss} - to retreive password' -f ($passwordTime - $startTime))
    Write-Host ('{0:mm}:{0:ss} - to establish remote connection' -f ($remoteTime - $startTime))
    $instance
}

function Stop-WinEC2Instance
{
    param (
        [String][Parameter(Mandatory=$true)]$InstanceId,
        $Region=$defaultRegion
    )
    trap { break }

    $a = Stop-EC2Instance -Instance $InstanceId -Region $Region -Force

    $cmd = { $(Get-EC2Instance -Region $Region -Filter @{Name = "instance-id"; Values = $InstanceId}).Instances[0].State.Name -eq "Stopped" }
    $a = Wait $cmd "Waiting for Stopped state" 450
}

function Start-WinEC2Instance
{
    param (
        [String][Parameter(Mandatory=$true)]$InstanceId,
        [String][Parameter(Mandatory=$true)]$Password,
        $Region=$defaultRegion
    )
    trap { break }
    Set-DefaultAWSRegion $Region

    $startTime = Get-Date

    $a = Start-EC2Instance -Instance $InstanceId

    $cmd = { $(Get-EC2Instance -Region $Region -Filter @{Name = "instance-id"; Values = $InstanceId}).Instances[0].State.Name -eq "running" }
    $a = Wait $cmd "Waiting for running state" 450

    #Wait for ping to succeed
    $instance = (Get-EC2Instance -Filter @{Name = "instance-id"; Values = $InstanceId}).Instances[0]
    $publicDNS = $instance.PublicDnsName

    Write-Host "publicDNS = $($instance.PublicDnsName)"


    $cmd = { echo "publicDNS=$publicDNS"; ping  $publicDNS}
    $a = Wait $cmd "Waiting for ping" 450

    $securepassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $creds = New-Object System.Management.Automation.PSCredential ("Administrator", $securepassword)
    
    $cmd = {New-PSSession $publicDNS -Credential $creds -Port 80}
    $s = Wait $cmd "Establishing remote connection" 300
    Remove-PSSession $s

    Write-Host ('{0:mm}:{0:ss} - to start' -f ((Get-Date) - $startTime))
}

function ReStart-WinEC2Instance
{
    param (
        [String][Parameter(Mandatory=$true)]$InstanceId,
        [String][Parameter(Mandatory=$true)]$Password,
        $Region=$defaultRegion
    )
    trap { break }
    $startTime = Get-Date

    $a = Stop-WinEC2Instance -InstanceId $InstanceId -Region $Region

    $a = Start-WinEC2Instance -InstanceId $InstanceId -Region $Region -Password $Password

    Write-Host ('{0:mm}:{0:ss} - to restart' -f ((Get-Date) - $startTime))
}


function Connect-WinEC2Instance
{
    param (
        $Region=$defaultRegion,
        $InstanceId,
        $ComputerName 
    )

    $instance = Get-winEC2Instance -Region $Region | `
        ? { $_.InstanceId -eq $InstanceId -or $_.tagComputerName -eq $ComputerName } | `
        select -First 1
    mstsc /v:$($instance.PublicIpAddress)
}


function Get-WinEC2Instance
{
    param (
        $Region=$defaultRegion
    )

    $instances = (Get-EC2Instance -Region $Region).Instances

    foreach ($instance in $instances)
    {
       $obj = New-Object PSObject -Property  @{
           InstanceId=$instance.InstanceId
           State = $instance.State.Name
           PublicIpAddress = $instance.PublicIpAddress
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

function Terminate-WinEC2InstanceAll
{
    $regions = Get-AWSRegion
    foreach ($region in $regions)
    {
        if ($region.Region -eq 'cn-north-1')
        {
            continue;
        }
        Write-Host '-----------------------'
        Write-Host "Deleting EC2 Instance form $($region.Region)"
        Write-Host '-----------------------'
        Get-EC2Instance -Region $Region.Region | Stop-EC2Instance -Region $Region.Region -Force -Terminate
    }
}


function Remove-WinEC2KeyPairAll
{
    $regions = Get-AWSRegion
    foreach ($region in $regions)
    {
        if ($wegion.Region -eq 'cn-north-1')
        {
            continue;
        }
        Write-Host '-----------------------'
        Write-Host "Deleting keypair from $($region.Region)"
        Write-Host '-----------------------'
        Get-EC2KeyPair -Region $Region.Region | % { Remove-EC2KeyPair $_.KeyName -Region $Region.Region  -Force }
    }
}

function Cleanup-WinEC2
{
    Terminate-WinEC2InstanceAll
    Remove-WinEC2KeyPairAll
}


# Creates or updates the security group
# Default it enables RDP, PowerShell, HTTP and ICMP.
# Define appropriate switch to disable specific protocol
# If SourceIPRange is not defined, it configures based on http://checkip.amazonaws.com
function Update-WinEC2FireWallSource
{
    param (
        $SecurityGroupName = 'sg_rdp_ps_http_icmp',
        $Region=$defaultRegion,
        $SourceIPRange = $null,
        [switch] $NoRDP,
        [switch] $NoPS,
        [switch] $NoHTTP,
        [switch] $NoICMP
    )
    trap {break }
    $ErrorActionPreference = 'Stop'

    Set-DefaultAWSRegion $defaultRegion

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

    Write-Host "Updated $SecurityGroupName IpRange to $SourceIPRange"
}

# Retry the scriptblock $cmd until no error and return true
# non-zero exit value for the process is considered as a failure
function wait ([ScriptBlock] $Cmd, [string] $Message, [int] $RetrySeconds)
{
    $t2 = $t1 = Get-Date
    Write-Host "$t1 $Message"-NoNewline
    $timeout = $false
    while ($true)
    {
        $global:LASTEXITCODE = 0

        try
        {
            $result = & $cmd 2>$null
            if ($LASTEXITCODE -ne 0)
            {
                global:$? = $false
            }
        }
        catch
        {
        }

        if ($? -and $result)
        {
            $result
            break;
        }
        $t2 = Get-Date
        if (($t2 - $t1).Seconds -gt $RetrySeconds)
        {
            $timeout = $true
        }
        Write-Host "." -NoNewline
        Sleep -Seconds 10
    }

    Write-Host " [$(($t2-$t1).Seconds) Seconds]"
    if ($timeout)
    {
        throw "Timeout - $Message"
    }
}
