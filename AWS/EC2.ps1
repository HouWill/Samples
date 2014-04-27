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


# Lanch EC2 Instance and set the new password
function New-WinEC2Instance
{
    param (
        $instanceType = 'm3.medium', 
        $ImagePrefix = 'Windows_Server-2012-RTM-English-64Bit-Base',
        $Region='us-east-1',
        $Password = $null,  # if the password is already baked in the image, specify the password
        $NewPassword = $null, # change the passowrd to this new value
        $SecurityGroupName = 'rdp_ps_sg'
        )

    # Retry the scriptblock $cmd until no error and return true
    # non-zero exit value for the process is considered as a failure
    function wait ([ScriptBlock] $Cmd, [string] $Message, [int] $RetrySeconds)
    {
        $t1 = Get-Date
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
                throw "Timeout - $Message"
            }
            Write-Host "$(Get-Date) $Message" -ForegroundColor Yellow
            Sleep -Seconds 10
        }
    }

    Set-DefaultAWSRegion $Region

    if ((Get-EC2SecurityGroup | where { $_.GroupName -eq $SecurityGroupName }) -eq $null)
    {
        #Create the firewall security group, Allows ping traffic, RDP and PowerShell remote connection
        $groupid = New-EC2SecurityGroup $SecurityGroupName  -Description "Security group enables rdp, ps and icmp"

        Grant-EC2SecurityGroupIngress -GroupName $SecurityGroupName -IpPermissions @{IpProtocol = "icmp"; FromPort = -1; ToPort = -1; IpRanges = @("0.0.0.0/0")}
        Grant-EC2SecurityGroupIngress -GroupName $SecurityGroupName -IpPermissions @{IpProtocol = "tcp"; FromPort = 3389; ToPort = 3389; IpRanges = @("0.0.0.0/0")}
        Grant-EC2SecurityGroupIngress -GroupName $SecurityGroupName -IpPermissions @{IpProtocol = "tcp"; FromPort = 5985; ToPort = 5985; IpRanges = @("0.0.0.0/0")}
        Grant-EC2SecurityGroupIngress -GroupName $SecurityGroupName -IpPermissions @{IpProtocol = "tcp"; FromPort = 80; ToPort = 80; IpRanges = @("0.0.0.0/0")}

        Update-FireWallSource -SecurityGroupName $SecurityGroupName
    }

    $startTime = Get-Date
    Write-Host "$($startTime) - Starting" -ForegroundColor Green

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
    net stop winrm
    net start winrm
</powershell>
"@
    $userdataBase64Encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($userdata))
    $a = New-EC2Instance -ImageId $imageid -MinCount 1 -MaxCount 1 -InstanceType $InstanceType -KeyName keypair1 -SecurityGroups $SecurityGroupName -UserData $userdataBase64Encoded
    $instanceid = $a.Instances[0].InstanceId
    "instanceid=$instanceid"

    $cmd = { $(Get-EC2Instance -Filter @{Name = "instance-id"; Values = $instanceid}).Instances[0].State.Name -eq "Running" }
    $a = Wait $cmd "Waiting for running state..." 450
    $runningTime = Get-Date
    Write-Host "$($runningTime) - Running" -ForegroundColor Green
        
    #Wait for ping to succeed
    $a = Get-EC2Instance -Filter @{Name = "instance-id"; Values = $instanceid}
    $publicDNS = $a.Instances[0].PublicDnsName

    $cmd = { echo "publicDNS=$publicDNS"; ping  $publicDNS}
    $a = Wait $cmd "Waiting for ping..." 450
    $pingTime = Get-Date
    Write-Host "$($pingTime) - Ping" -ForegroundColor Green

    #Wait until the password is available
    if ($Password -eq $null)
    {
        $cmd = {Get-EC2PasswordData -InstanceId $instanceid -PemFile $keyfile -Decrypt}
        $Password = Wait $cmd "Waiting to retreive password..." 600
    }

    #Password is received, delete keypair
    Remove-EC2KeyPair -KeyName keypair1 -Force
    Remove-Item $keyfile
    "$Password  $publicDNS"

    $securepassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $creds = New-Object System.Management.Automation.PSCredential ("Administrator", $securepassword)
    $passwordTime = Get-Date
    Write-Host "$($passwordTime) - Password" -ForegroundColor Green
    
    $cmd = {New-PSSession $publicDNS -Credential $creds -Port 80}
    $s = Wait $cmd "Establishing remote connection..." 300

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
    Write-Host "$($remoteTime) - Remote" -ForegroundColor Green

    Write-Host "Results"
    Write-Host "EC2 Instance Type:$instanceType Region:$region" -ForegroundColor Green
    Write-Host "$($runningTime - $startTime) - Running" -ForegroundColor Green
    Write-Host "$($pingTime - $startTime) - Ping" -ForegroundColor Green
    Write-Host "$($passwordTime - $startTime) - Password" -ForegroundColor Green
    Write-Host "$($remoteTime - $startTime) - Remote" -ForegroundColor Green

    "$instanceType`t$Region`t$($runningTime - $startTime)`t$($pingTime - $startTime)`t$($passwordTime - $startTime)`t$($remoteTime - $startTime)" >> c:\temp\perf.csv
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
        Write-Host "Deleting EC2 Instance form $($region.Region)" -ForegroundColor Yellow
        Write-Host '-----------------------'
        Get-EC2Instance -Region $Region.Region | Stop-EC2Instance -Region $Region.Region -Force -Terminate
    }
}


function Remove-WinEC2KeyPairAll
{
    $regions = Get-AWSRegion
    foreach ($region in $regions)
    {
        if ($region.Region -eq 'cn-north-1')
        {
            continue;
        }
        Write-Host '-----------------------'
        Write-Host "Deleting keypair from $($region.Region)" -ForegroundColor Yellow
        Write-Host '-----------------------'
        Get-EC2KeyPair -Region $Region.Region | % { Remove-EC2KeyPair $_.KeyName -Force }
    }
}

function Cleanup-WinEC2
{
    Terminate-WinEC2InstanceAll
    Remove-WinEC2KeyPairAll
}


function Update-WinEC2FireWallSource
{
    param ($SecurityGroupName = 'rdp_ps_sg')

    $sourceIP = [System.Text.Encoding]::Ascii.GetString((Invoke-WebRequest 'http://checkip.amazonaws.com/').Content).Trim()
    
    $sg = Get-EC2SecurityGroup -GroupNames $SecurityGroupName
    foreach ($ipPermission in $sg.IpPermissions)
    {
         Revoke-EC2SecurityGroupIngress -GroupName $SecurityGroupName -IpPermissions $ipPermission
         $ipPermission.IpRange = @("$sourceIP/32")
         Grant-EC2SecurityGroupIngress -GroupName $SecurityGroupName -IpPermissions $ipPermission
    }
    Write-Host "Updated $SecurityGroupName IpRange to $sourceIP"
}