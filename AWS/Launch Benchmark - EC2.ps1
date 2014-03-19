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

param ($instanceType = 'm1.small', $region='us-east-1')

function WaitForState ($instanceid, $desiredstate)
{
    while ($true)
    {
        $a = Get-EC2Instance -Filter @{Name = "instance-id"; Values = $instanceid} 
        $state = $a.Instances[0].State.Name
        if ($state -eq $desiredstate)
        {
            break;
        }
        "$(Get-Date) Current State = $state, Waiting for Desired State=$desiredstate"
        Sleep -Seconds 5
    }
}

Set-DefaultAWSRegion $region
$keyfile = [System.IO.Path]::GetTempFileName()

if ((Get-EC2SecurityGroup | where { $_.GroupName -eq 'rdp_ps_sg' }) -eq $null)
{
    #Create the firewall security group, Allows ping traffic, RDP and PowerShell remote connection
    $groupid = New-EC2SecurityGroup rdp_ps_sg  -Description "Security group enables rdp, ps and icmp"

    Grant-EC2SecurityGroupIngress -GroupName rdp_ps_sg -IpPermissions @{IpProtocol = "icmp"; FromPort = -1; ToPort = -1; IpRanges = @("0.0.0.0/0")}
    Grant-EC2SecurityGroupIngress -GroupName rdp_ps_sg -IpPermissions @{IpProtocol = "tcp"; FromPort = 3389; ToPort = 3389; IpRanges = @("0.0.0.0/0")}
    Grant-EC2SecurityGroupIngress -GroupName rdp_ps_sg -IpPermissions @{IpProtocol = "tcp"; FromPort = 5985; ToPort = 5985; IpRanges = @("0.0.0.0/0")}
    Grant-EC2SecurityGroupIngress -GroupName rdp_ps_sg -IpPermissions @{IpProtocol = "tcp"; FromPort = 80; ToPort = 80; IpRanges = @("0.0.0.0/0")}
}

$startTime = Get-Date
Write-Host "$($startTime) - Starting" -ForegroundColor Green

#create a KeyPair, this is used to encrypt the Administrator password.
    $keypair1 = New-EC2KeyPair -KeyName keypair1
    "$($keypair1.KeyMaterial)" | out-file -encoding ascii -filepath $keyfile
    "KeyName: $($keypair1.KeyName)" | out-file -encoding ascii -filepath $keyfile -Append
    "KeyFingerprint: $($keypair1.KeyFingerprint)" | out-file -encoding ascii -filepath $keyfile -Append

    #Find the Windows Server 2012 imageid
    $a = Get-EC2Image -Filters @{Name = "name"; Values = "Windows_Server-2012-RTM-English-64Bit-Base*"}
    $imageid = $a[$a.Length-1].ImageId #get the last one if there are more than one image

    #Launch the instance
    $userdata = @"
<powershell>
    Set-NetFirewallRule -Name WINRM-HTTP-In-TCP-PUBLIC -RemoteAddress Any
    New-NetFirewallRule -Name "WinRM80" -DisplayName "WinRM80" -Protocol TCP -LocalPort 80
    Set-Item (dir wsman:\localhost\Listener\*\Port -Recurse).pspath 80 -Force
    net stop winrm
    net start winrm
</powershell>
"@
    $userdataBase64Encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($userdata))
    $a = New-EC2Instance -ImageId $imageid -MinCount 1 -MaxCount 1 -InstanceType $instanceType -KeyName keypair1 -SecurityGroups rdp_ps_sg -UserData $userdataBase64Encoded
    $instanceid = $a.Instances[0].InstanceId
    WaitForState $instanceid "Running"
    $runningTime = Get-Date
    Write-Host "$($runningTime) - Running" -ForegroundColor Green

#Wait for ping to succeed
    $a = Get-EC2Instance -Filter @{Name = "instance-id"; Values = $instanceid}
    $publicDNS = $a.Instances[0].PublicDnsName

    while ($true)
    {
        ping $publicDNS >$null
        if ($LASTEXITCODE -eq 0)
        {
            break
        }
        "$(Get-Date) Waiting for ping to succeed"
        Sleep -Seconds 10
    }
    $pingTime = Get-Date
    Write-Host "$($pingTime) - Ping" -ForegroundColor Green

#Wait until the password is available
    $password = $null
    #blindsly eats all the exceptions, bad idea for a production code.
    while ($password -eq $null)
    {
        try
        {
            $password = Get-EC2PasswordData -InstanceId $instanceid -PemFile $keyfile -Decrypt
        }
        catch
        {
            "$(Get-Date) Waiting for PasswordData to be available"
            Sleep -Seconds 10
        }
    }
    Remove-EC2KeyPair -KeyName keypair1 -Force
    Remove-Item $keyfile
    $password
    $securepassword = ConvertTo-SecureString $password -AsPlainText -Force
    $creds = New-Object System.Management.Automation.PSCredential ("Administrator", $securepassword)
    $passwordTime = Get-Date
    Write-Host "$($passwordTime) - Password" -ForegroundColor Green

#Wait until PSSession is available
    while ($true)
    {
        $s = New-PSSession $publicDNS -Credential $creds -Port 80 2>$null
        if ($s -ne $null)
        {
            break
        }

        "$(Get-Date) Waiting for remote PS connection"
        Sleep -Seconds 10
    }
    Invoke-Command -Session $s {(Invoke-WebRequest http://169.254.169.254/latest/user-data).RawContent}
    Remove-PSSession $s
    $remoteTime = Get-Date
    Write-Host "$($remoteTime) - Remote" -ForegroundColor Green

#Terminate the Instance
    Get-EC2Instance -Filter @{Name = "instance-id"; Values = $instanceid} | Stop-EC2Instance -Force -Terminate
    WaitForState $instanceid "Terminated"
    $terminateTime = Get-Date
    Write-Host "$($terminateTime) - Terminate" -ForegroundColor Green

Write-Host "Results"
Write-Host "EC2 Instance Type:$instanceType Region:$region" -ForegroundColor Green
Write-Host "$($runningTime - $startTime) - Running" -ForegroundColor Green
Write-Host "$($pingTime - $startTime) - Ping" -ForegroundColor Green
Write-Host "$($passwordTime - $startTime) - Password" -ForegroundColor Green
Write-Host "$($remoteTime - $startTime) - Remote" -ForegroundColor Green
Write-Host "$($terminateTime - $startTime) - Terminate" -ForegroundColor Green
