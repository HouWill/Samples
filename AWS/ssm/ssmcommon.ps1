function SSMCreateKeypair (
        [string]$KeyFile = 'c:\keys\test'
    )
{
    $keyName = $KeyFile.split('/\')[-1]

    if (Get-EC2KeyPair  | ? { $_.KeyName -eq $keyName }) { 
        Write-Verbose "Skipping as keypair ($keyName) already present." 
        return
    }

    if (Test-Path "$KeyFile.pub") {
        $publicKeyMaterial = cat "$KeyFile.pub" -Raw
        $encodedPublicKeyMaterial = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($publicKeyMaterial))
        Import-EC2KeyPair -KeyName $keyName -PublicKeyMaterial $encodedPublicKeyMaterial
        Write-Verbose "Importing KeyName=$keyName, keyfile=$KeyFile"
    } else {
        Write-Verbose "Creating KeyName=$keyName, keyfile=$KeyFile"
        $keypair = New-EC2KeyPair -KeyName $keyName
        "$($keypair.KeyMaterial)" | Out-File -encoding ascii -filepath "$KeyFile.pem"
    }
}

function SSMRemoveKeypair (
        [string]$KeyFile = 'c:\keys\test'
    )
{
    #delete keypair
    $keyName = $KeyFile.split('/\')[-1]
    Remove-EC2KeyPair -KeyName $keyName -Force
    Write-Verbose "Removed keypair=$keypair, keyfile=$keyfile"
}


function SSMCreateRole ([string]$RoleName = 'winec2role')
{
    if (Get-IAMRoles | ? {$_.RoleName -eq $RoleName}) {
        Write-Verbose "Skipping as role ($RoleName) is already present."
        return
    }
    #Define which accounts or AWS services can assume the role.
    $assumePolicy = @"
{
    "Version":"2012-10-17",
    "Statement":[
      {
        "Sid":"",
        "Effect":"Allow",
        "Principal":{"Service":["ec2.amazonaws.com", "ssm.amazonaws.com", "lambda.amazonaws.com", "kinesisanalytics.amazonaws.com"]},
        "Action":"sts:AssumeRole"
      }
    ]
}
"@
    #step a - Create the role and specify who can assume
    $null = New-IAMRole -RoleName $RoleName `
                -AssumeRolePolicyDocument $assumePolicy
    
    #step b - write the role policy
    #Write-IAMRolePolicy -RoleName $RoleName `
    #            -PolicyDocument $policy -PolicyName 'ssm'

    Register-IAMRolePolicy -RoleName $RoleName -PolicyArn 'arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM'

    #step c - Create instance profile
    $null = New-IAMInstanceProfile -InstanceProfileName $RoleName

    #step d - Add the role to the profile
    Add-IAMRoleToInstanceProfile -InstanceProfileName $RoleName `
            -RoleName $RoleName
    Write-Verbose "Role $RoleName created" 
}
function SSMRemoveRole ([string]$RoleName = 'winec2role')
{
    if (!(Get-IAMRoles | ? {$_.RoleName -eq $RoleName})) {
        Write-Verbose "Skipping as role ($RoleName) not found"
        return
    }
    #Remove the instance role and IAM Role
    Invoke-PSUtilIgnoreError {Remove-IAMRoleFromInstanceProfile -InstanceProfileName $RoleName -RoleName $RoleName -Force}
    Invoke-PSUtilIgnoreError {Remove-IAMInstanceProfile $RoleName -Force}
    Invoke-PSUtilIgnoreError {Unregister-IAMRolePolicy -RoleName $RoleName -PolicyArn 'arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM'}
    #Remove-IAMRolePolicy $RoleName ssm -Force
    Remove-IAMRole $RoleName -Force
    Write-Verbose "Role $RoleName removed" 
}




function SSMCreateSecurityGroup ([string]$SecurityGroupName = 'winec2securitygroup')
{
    if ($securityGroup = (Get-EC2SecurityGroup | ? { $_.GroupName -eq $securityGroupName })) {
        Write-Verbose "Skipping as SecurityGroup ($securityGroupName) already present."
        $securityGroupId = $securityGroup.GroupId
    } else {
        #Security group and the instance should be in the same network (VPC)
        $vpc = Get-EC2Vpc | ? { $_.IsDefault } | select -First 1
        $securityGroupId = New-EC2SecurityGroup $securityGroupName  -Description "winec2 Securitygroup" -VpcId $vpc.VpcId
        $securityGroup = Get-EC2SecurityGroup -GroupName $securityGroupName 
        Write-Verbose "Security Group $securityGroupName created"
    }

    #Compute new ip ranges
    $bytes = (Invoke-WebRequest 'http://checkip.amazonaws.com/' -UseBasicParsing).Content
    $myIP = @(([System.Text.Encoding]::Ascii.GetString($bytes).Trim() + "/32"))
    Write-Verbose "$myIP retreived from checkip.amazonaws.com"
    $ips = @($myIP)
    $ips += (Get-EC2Vpc).CidrBlock

    $SourceIPRanges = @()
    foreach ($ip in $ips) {
        $SourceIPRanges += @{ IpProtocol="tcp"; FromPort="22"; ToPort="5986"; IpRanges=$ip}
        $SourceIPRanges += @{ IpProtocol='icmp'; FromPort = -1; ToPort = -1; IpRanges = $ip}
    }

    #Current expanded list
    $currentIPRanges = @()
    foreach ($ipPermission in $securityGroup.IpPermission) {
        foreach ($iprange in $ipPermission.IpRange) {
            $currentIPRanges += @{ IpProtocol=$ipPermission.IpProtocol; FromPort =$ipPermission.FromPort; ToPort = $ipPermission.ToPort; IpRanges = $iprange}
        }
    }

    # Remove IPRange from current, if it should not be
    foreach ($currentIPRange in $currentIPRanges) {
        $found = $false
        foreach ($SourceIPRange in $SourceIPRanges) {
            if ($SourceIPRange.IpProtocol -eq $currentIPRange.IpProtocol -and
                $SourceIPRange.FromPort -eq $currentIPRange.FromPort -and
                $SourceIPRange.ToPort -eq $currentIPRange.ToPort -and
                $SourceIPRange.IpRanges -eq $currentIPRange.IpRanges) {
                    $found = $true
                    break
            }
        }
        if ($found) {
            Write-Verbose "Skipping protocol=$($currentIPRange.IpProtocol) IPRange=$($currentIPRange.IpRanges)"
        } else {
            Revoke-EC2SecurityGroupIngress -GroupId $securityGroupId -IpPermission $currentIPRange
            Write-Verbose "Granted permissions for $($SourceIPRange.IpProtocol) ports $($SourceIPRange.FromPort) to $($SourceIPRange.ToPort), IP=($SourceIPRange.IpRanges[0])"
        }
    }

    # Add IPRange to current, if it is not present
    foreach ($SourceIPRange in $SourceIPRanges) {
        $found = $false
        foreach ($currentIPRange in $currentIPRanges) {
            if ($SourceIPRange.IpProtocol -eq $currentIPRange.IpProtocol -and
                $SourceIPRange.FromPort -eq $currentIPRange.FromPort -and
                $SourceIPRange.ToPort -eq $currentIPRange.ToPort -and
                $SourceIPRange.IpRanges -eq $currentIPRange.IpRanges) {
                    $found = $true
                    break
            }
        }
        if (! $found) {
            Grant-EC2SecurityGroupIngress -GroupId $securityGroupId -IpPermissions $SourceIPRange
            Write-Verbose "Granted permissions for ports 22 to 5986, for IP=($SourceIPRange.IpRanges)"
        }
    }
}

function SSMRemoveSecurityGroup ([string]$SecurityGroupName = 'winec2securitygroup')
{
    $securityGroupId = (Get-EC2SecurityGroup | `
        ? { $_.GroupName -eq $securityGroupName }).GroupId

    if ($securityGroupId) {
        SSMWait {(Remove-EC2SecurityGroup $securityGroupId -Force) -eq $null} `
                'Delete Security Group' 300
        Write-Verbose "Security Group $securityGroupName removed"
    } else {
        Write-Verbose "Skipping as SecurityGroup $securityGroupName not found"
    }
}




function SSMCreateWindowsInstance (
        [string]$ImageName = 'WINDOWS_2012R2_BASE',
        [string]$SecurityGroupName = 'winec2securitygroup',
        [string]$InstanceType = 'm4.large',
        [string]$Tag = 'ssm-demo',
        [string]$KeyName = 'winec2keypair',
        [string]$KeyFile = "c:\keys\$((Get-DefaultAWSRegion).Region).$keyName.pem",
        [string]$RoleName = 'winec2role',
        [int]$InstanceCount=1
    )
{
    #Check if the instance is already present
    $filter1 = @{Name='tag:Name';Value=$Tag}
    $filter2 = @{Name='instance-state-name';Values=@('running','pending','stopped')}
    $instance = Get-EC2Instance -Filter @($filter1, $filter2)
    if ($instance) {
        $instanceId = $instance.Instances.InstanceId
        Write-Verbose "Skipping instance $instanceId creation, already present"
        $instanceId
        return
    }

    $securityGroupId = (Get-EC2SecurityGroup | `
        ? { $_.GroupName -eq $SecurityGroupName }).GroupId
    if (! $securityGroupId) {
        throw "Security Group $SecurityGroupName not found"
    }

    #Get the latest R2 base image
    $image = Get-EC2ImageByName $ImageName
    Write-Verbose "Image=$($image.Name), SecurityGroupName=$SecurityGroupName, InstanceType=$InstanceType, KeyName=$KeyName, RoleName=$RoleName, InstanceCount=$InstanceCount"

    #User Data to enable PowerShell remoting on port 80
    #User data must be passed in as 64bit encoding.
    $userdata = @"
    <powershell>
    Enable-NetFirewallRule FPS-ICMP4-ERQ-In
    Set-NetFirewallRule -Name WINRM-HTTP-In-TCP-PUBLIC -RemoteAddress Any
    New-NetFirewallRule -Name "WinRM80" -DisplayName "WinRM80" -Protocol TCP -LocalPort 80
    Set-Item WSMan:\localhost\Service\EnableCompatibilityHttpListener -Value true
    </powershell>
"@
    $utf8 = [System.Text.Encoding]::UTF8.GetBytes($userdata)
    $userdataBase64Encoded = [System.Convert]::ToBase64String($utf8)

    #Launch EC2 Instance with the role, firewall group created
    # and on the right subnet
    $instances = (New-EC2Instance -ImageId $image.ImageId `
                    -InstanceProfile_Id $RoleName `
                    -AssociatePublicIp $true `
                    -SecurityGroupId $securityGroupId `
                    -KeyName $keyName `
                    -UserData $userdataBase64Encoded `
                    -InstanceType $InstanceType `
                    -MinCount $InstanceCount -MaxCount $InstanceCount).Instances

    New-EC2Tag -ResourceId $instances.InstanceId -Tag @{Key='Name'; Value=$Tag}

    foreach ($instance in $instances) {
        Write-Verbose "InstanceId=$($instance.InstanceId)"
        #Wait to retrieve password
        $cmd = { 
                $password = Get-EC2PasswordData -InstanceId $instance.InstanceId `
                    -PemFile $keyfile -Decrypt 
                $password -ne $null
                }
        SSMWait $cmd 'Password Generation' 600

        $password = Get-EC2PasswordData -InstanceId $instance.InstanceId `
                        -PemFile $keyfile -Decrypt 
        $securepassword = ConvertTo-SecureString $Password -AsPlainText -Force
        $creds = New-Object System.Management.Automation.PSCredential ("Administrator", $securepassword)


<##        #update the instance to get the public IP Address
        $instance = (Get-EC2Instance $instance.InstanceId).Instances

        #Wait for remote PS connection
        $cmd = {
            icm $instance.PublicIpAddress {dir c:\} -Credential $creds -Port 80 
        }
        SSMWait $cmd 'Remote Connection' 450
##>
    }
    $cmd = { 
        $count = (Get-SSMInstanceInformation -InstanceInformationFilterList @{ Key='InstanceIds'; ValueSet=$instances.InstanceId}).Count
        $count -eq $InstanceCount
    }
    SSMWait $cmd 'Instance Registration' 300
    $instances.InstanceId
}
function SSMCreateLinuxInstance (
        [string]$ImageName = `
                #'amzn-ami-hvm-*gp2',
                'ubuntu/images/hvm-ssd/ubuntu-*-14.*',
        [string]$SecurityGroupName = 'winec2securitygroup',
        [string]$InstanceType = 'm4.large',
        [string]$Tag = 'ssm-demo',
        [string]$KeyName = 'winec2keypair',
        [string]$KeyFile = "c:\keys\$((Get-DefaultAWSRegion).Region).$keyName.pem",
        [string]$RoleName = 'winec2role',
        [int]$InstanceCount=1
    )
{
    $filter1 = @{Name='tag:Name';Value=$Tag}
    $filter2 = @{Name='instance-state-name';Values=@('running','pending','stopped')}
    $instance = Get-EC2Instance -Filter @($filter1, $filter2)
    if ($instance) {
        $instanceId = $instance.Instances.InstanceId
        Write-Verbose "Skipping instance $instanceId creation, already present"
        $instanceId
        return
    }
    $securityGroupId = (Get-EC2SecurityGroup | `
        ? { $_.GroupName -eq $SecurityGroupName }).GroupId
    if (! $securityGroupId) {
        throw "Security Group $SecurityGroupName not found"
    }

    #Get the latest image
    $image = Get-EC2Image -Filters @{Name = "name"; Values = "$ImageName*"} | sort -Property CreationDate -Descending | select -First 1
    Write-Verbose "Image=$($image.Name), SecurityGroupName=$SecurityGroupName, InstanceType=$InstanceType, KeyName=$KeyName, RoleName=$RoleName, InstanceCount=$InstanceCount"

    $userdata = @'
#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

if [ -f /etc/debian_version ]; then
    echo "Debian"
    curl https://amazon-ssm-us-east-1.s3.amazonaws.com/latest/debian_amd64/amazon-ssm-agent.deb -o amazon-ssm-agent.deb
    dpkg -i amazon-ssm-agent.deb
else
    echo "Amazon Linux or Redhat"
    curl https://amazon-ssm-us-east-1.s3.amazonaws.com/latest/linux_amd64/amazon-ssm-agent.rpm -o amazon-ssm-agent.rpm
    yum install -y amazon-ssm-agent.rpm
fi

'@.Replace("`r",'')

    #User data must be passed in as 64bit encoding.
    $utf8 = [System.Text.Encoding]::UTF8.GetBytes($userdata)
    $userdataBase64Encoded = [System.Convert]::ToBase64String($utf8)

    #Launch EC2 Instance with the role, firewall group created
    # and on the right subnet
    $instances = (New-EC2Instance -ImageId $image.ImageId `
                    -InstanceProfile_Id $RoleName `
                    -AssociatePublicIp $true `
                    -SecurityGroupId $securityGroupId `
                    -KeyName $keyName `
                    -UserData $userdataBase64Encoded `
                    -InstanceType $InstanceType `
                    -MinCount $InstanceCount -MaxCount $InstanceCount).Instances
    New-EC2Tag -ResourceId $instances.InstanceId -Tag @{Key='Name'; Value=$Tag}
<##
    foreach ($instance in $instances) {
        Write-Verbose "InstanceId=$($instance.InstanceId)"

        $cmd = { 
            $a = $(Get-EC2Instance -Filter @{Name = "instance-id"; Values = $instance.InstanceId}).Instances
            ping $a.PublicIpAddress > $null
            $LASTEXITCODE -eq 0
        }
        SSMWait $cmd 'ping' 300
    
    }
##>
    $cmd = { 
        $count = (Get-SSMInstanceInformation -InstanceInformationFilterList @{ Key='InstanceIds'; ValueSet=$instances.InstanceId}).Count
        $count -eq $InstanceCount
    }
    SSMWait $cmd 'Instance Registration' 300
    $instances.InstanceId
}
function SSMRemoveInstance (
        [string]$Tag = 'ssm-demo',
        [string]$KeyName = 'winec2keypair',
        [string]$KeyFile = "c:\keys\$((Get-DefaultAWSRegion).Region).$keyName.pem"
    )
{
    $filter1 = @{Name='tag:Name';Value=$Tag}
    $filter2 = @{Name='instance-state-name';Values=@('running','pending','stopped')}
    $instances = (Get-EC2Instance -Filter @($filter1, $filter2)).Instances
    
    if ($instances) {
        foreach ($instance in $instances) {
            $instanceId = $instance.InstanceId
            $null = Stop-EC2Instance -Instance $instanceId -Force -Terminate
            Write-Verbose "Terminated instance $instanceId"
        }
    } else {
        Write-Verbose "Skipping as instance with name=$Tag not found"
    }
}




function SSMRunCommand (
        $InstanceIds,
        [string]$DocumentName = 'AWS-RunPowerShellScript',
        [Hashtable]$Parameters,
        [string]$Comment = $DocumentName,
        [string]$Outputs3BucketName,
        [string]$Outputs3KeyPrefix = 'ssmoutput',
        [int]$Timeout = 300,
        [int]$SleepTimeInMilliSeconds = 2000
    )
{
    Write-Verbose "SSMRunCommand: InstanceIds=$InstanceIds, DocumentName=$DocumentName, Outputs3BucketName=$Outputs3BucketName, Outputs3KeyPrefix=$Outputs3KeyPrefix"
    $parameters = @{
        InstanceId = $InstanceIds
        DocumentName = $DocumentName
        Comment = $DocumentName
        Parameters = $Parameters
        TimeoutSecond = $Timeout
    }
    ($parameters.Parameters | Out-String).Trim() | Write-Verbose
    if($Outputs3BucketName.Length -gt 0 -and $Outputs3KeyPrefix.Length -gt 0) {
        $parameters.'Outputs3BucketName' = $Outputs3BucketName
        $parameters.'Outputs3KeyPrefix' = $Outputs3KeyPrefix

    }
    $result=Send-SSMCommand @parameters 

    Write-Verbose "CommandId=$($result.CommandId)"
    $cmd = {
        $status1 = (Get-SSMCommand -CommandId $result.CommandId).Status
        ($status1 -ne 'Pending' -and $status1 -ne 'InProgress')
    }
    $null = SSMWait -Cmd $cmd -Message 'Command Execution' -RetrySeconds $Timeout -SleepTimeInMilliSeconds $SleepTimeInMilliSeconds
    
    $command = Get-SSMCommand -CommandId $result.CommandId
    if ($command.Status -ne 'Success') {
        throw "Command $($command.CommandId) did not succeed, Status=$($command.Status)"
    }
    $result
}


function SSMDumpOutput (
        $Command,
        [boolean]$DeleteS3Keys = $true
    )
{
    $commandId = $Command.CommandId
    $bucket = $Command.OutputS3BucketName
    $key = $Command.OutputS3KeyPrefix
    Write-Verbose "SSMDumpOutput CommandId=$commandId, Bucket=$bucket, Key=$key"
    foreach ($instanceId in $Command.InstanceIds) {
        Write-Verbose "InstanceId=$instanceId"
        $global:invocation = Get-SSMCommandInvocation -InstanceId $instanceId `
                        -CommandId $commandId -Details:$true

        foreach ($plugin in $invocation.CommandPlugins) {
            Write-Verbose "Plugin Name=$($plugin.Name)"
            Write-Verbose "ResponseCode=$($plugin.ResponseCode)"
            Write-Verbose "Plugin Status=$($plugin.Status)"
            if ($key.Length -eq 0 -and $plugin.Output.Length -gt 0) { 
                #if S3 key is defined, this will avoid duplication
                Write-Verbose "PluginOutput:"
                $plugin.Output.Trim()
                Write-Verbose ''
            }
        }
        if ($bucket -and $key) {
            $s3objects = Get-S3Object -BucketName $bucket `
                      -Key "$key\$commandId\$instanceId\"
            $tempFile = [System.IO.Path]::GetTempFileName()
            foreach ($s3object in $s3objects)
            {
                if ($s3object.Size -gt 3) 
                {
                    $offset = $key.Length + $commandId.Length + `
                                    $instanceId.Length + 3
                    Write-Verbose "$($s3object.key.Substring($offset)):"
                    $null = Read-S3Object -BucketName $bucket `
                             -Key $s3object.Key -File $tempFile
                    if ($s3object.key.EndsWith('stdout.txt') -or $s3object.key.EndsWith('stdout')) {
                        cat $tempFile -Raw | Write-Host
                    } elseif ($s3object.key.EndsWith('stderr.txt') -or $s3object.key.EndsWith('stderr')) {
                        cat $tempFile -Raw | Write-Error
                    } else {
                        cat $tempFile -Raw | Write-Verbose
                    }
                    del $tempFile -Force
                    Write-Verbose ''
                }
                if ($DeleteS3Keys) {
                    $null = Remove-S3Object -BucketName $bucket `
                                 -Key $s3object.Key -Force
                }
            }
        }
        Write-Verbose ''
    }
}

function SSMWait (
    [ScriptBlock] $Cmd, 
    [string] $Message, 
    [int] $RetrySeconds,
    [int] $SleepTimeInMilliSeconds = 5000)
{
    $_msg = "Waiting for $Message to succeed"
    $_t1 = Get-Date
    while ($true)
    {
        $_t2 = Get-Date
        $_t = [int]($_t2 - $_t1).TotalSeconds
        Write-Verbose "$_msg ($_t/$RetrySeconds) Seconds."
        try
        {
            $_result = & $Cmd 2>$_null | select -Last 1 
            if ($? -and $_result)
            {
                Write-Verbose("Succeeded $Message in " + `
                    "$([int]($_t2-$_t1).TotalSeconds) Seconds, Result=$_result")
                break;
            }
        }
        catch
        {
        }
        $_t = [int]($_t2 - $_t1).TotalSeconds
        if ($_t -gt $RetrySeconds)
        {
            throw "Timeout - $Message after $RetrySeconds seconds, " +  `
                "Current result=$_result"
            break
        }
        Sleep -Milliseconds $SleepTimeInMilliSeconds
    }
}





function SSMGetLogs (
    $instance, 
    [PSCredential] $Credential, 
    [string]$log = 'ssm.log')
{
    Write-Verbose "Log file $log"
    $cmd = {
        Get-EventLog -LogName Ec2ConfigService |
        % { $_.Message.trim() } | 
        sort 
     }
    icm $instance.PublicIpAddress $cmd -Credential $Credential -Port 80 > $log
    notepad $log
}
function SSMAssociate (
    $instance, 
    [string]$doc, 
    [PSCredential] $Credential, 
    [int]$RetrySeconds = 150,
    [boolean]$ClearEventLog = $true,
    [boolean]$DeleteDocument = $true)
{
    #Only one association is support per instance at this time
    #Delete the association if it exists.
    $association = Get-SSMAssociationList -AssociationFilterList `
                    @{Key='InstanceId'; Value=$instance.instanceid}
    if ($association)
    {
        Remove-SSMAssociation -InstanceId $association.InstanceId `
            -Name $association.Name -Force
        
        if ($DeleteDocument)
        {
            Remove-SSMDocument -Name $association.Name -Force
        }
    }

    $instanceId = $instance.InstanceId
    $ipaddress = $instance.PublicIpAddress

    if ($ClearEventLog) 
    {
        icm $ipaddress {Clear-EventLog -LogName Ec2ConfigService} `
            -Credential $Credential -Port 80
    }
    
    #generate a new document with unique name
    $name = 'doc-' + [Guid]::NewGuid()
    Write-Verbose "Document Name=$name"
    $null = New-SSMDocument -Content $doc -name $name

    #assocate the document to the instance
    $null = New-SSMAssociation -InstanceId $instance.InstanceId -Name $name

    #apply config
    $cmd = {& "$env:ProgramFiles\Amazon\Ec2ConfigService\ec2config-cli.exe" -a}
    $null = icm $ipaddress $cmd -Credential $Credential -Port 80

    #Wait for convergence    
    $cmd = {
        $status = (Get-SSMAssociation -InstanceId $instanceid -Name $name).Status
        $status.Name -eq 'Success' -or $status.Name -eq 'Failed'
    }
    $null = SSMWait $cmd -Message 'Converge Association' `
                -RetrySeconds $RetrySeconds

    #Output Status
    $status = (Get-SSMAssociation -InstanceId $instanceid -Name $name).Status
    Write-Verbose "Status=$($status.Name), Message=$($status.Message)"
    if ($status.Name -ne 'Success')
    {
        throw 'SSM Failed'
    }
}
function SSMGetAssociations ()
{
    foreach ($i in Get-EC2Instance)
    {
        $association = Get-SSMAssociationList -AssociationFilterList `
                        @{Key='InstanceId'; Value=$i.instances[0].instanceid}

        if ($association)
        {
            Get-SSMAssociation -InstanceId $association.InstanceId `
                -Name $association.Name
        }
    }
}
function SSMEnter-PSSession (
        [string]$Tag = $instanceName,
        [string]$KeyName = 'winec2keypair',
        [string]$KeyFile = "c:\keys\$((Get-DefaultAWSRegion).Region).$keyName.pem"
    )
{
    $instance = (Get-EC2Instance -Filter @{Name='tag:Name';Value=$Tag}).Instances[0]

    $password = Get-EC2PasswordData -InstanceId $instance.InstanceId `
                    -PemFile $keyfile -Decrypt 
    $securepassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $creds = New-Object System.Management.Automation.PSCredential ("Administrator", $securepassword)
    Enter-PSSession $instance.PublicIpAddress -Credential $creds -Port 80 
}

function SSMWindowsInstallAgent ([string]$ConnectionUri, [System.Management.Automation.PSCredential]$Credential, [string]$Region, [string]$DefaultInstanceName)
{
    Write-Verbose "ConnectionUri=$ConnectionUri, Region=$Region, DefaultInstanceName=$DefaultInstanceName"
    $code = New-SSMActivation -DefaultInstanceName $DefaultInstanceName -IamRole 'test' -RegistrationLimit 1 –Region $Region
    Write-Verbose "ActivationCode=$($code.ActivationCode), ActivationId=$($code.ActivationId)"

    $sb = {
        param ($Region, $ActivationCode, $ActivationId)

        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force

        $source = "https://amazon-ssm-$region.s3.amazonaws.com/latest/windows_amd64/AmazonSSMAgentSetup.exe"
        $dest = "$($env:TEMP)\AmazonSSMAgentSetup.exe"
        del $dest -ea 0
        $log = "$($env:TEMP)\SSMInstall.log"
        $webclient = New-Object System.Net.WebClient
        $webclient.DownloadFile($source, $dest)

        $a = @('/q', '/log', $log, "CODE=$ActivationCode", "ID=$ActivationId", "REGION=$Region", 'ALLOWEC2INSTALL=YES')
        Start-Process $dest -ArgumentList $a -Wait
        #cat $log
        $st = Get-Content ("$($env:ProgramData)\Amazon\SSM\InstanceData\registration")
        Write-Verbose "ProgramData\Amazon\SSM\InstanceData\registration=$st"
        Write-Verbose (Get-Service -Name "AmazonSSMAgent")
    }

    Invoke-Command -ScriptBlock $sb -ConnectionUri $ConnectionUri -Credential $Credential -ArgumentList @($Region, $code.ActivationCode, $code.ActivationId) -SessionOption (New-PSSessionOption -SkipCACheck)

    Remove-SSMActivation $code.ActivationId -Force -Region $Region

    $filter = @{Key='ActivationIds'; ValueSet=$code.ActivationId}
    $InstanceId = (Get-SSMInstanceInformation -InstanceInformationFilterList $filter -Region $Region).InstanceId
    Write-Verbose "Managed InstanceId=$InstanceId"

    $cmd = { 
        (Get-SSMInstanceInformation -InstanceInformationFilterList @{ Key='InstanceIds'; ValueSet=$instanceid}).Count -eq 1
    }
    $null = Invoke-PSUtilWait $cmd 'Instance Registration' 150

    $instanceId
}

function SSMLinuxInstallAgent ([string]$Key, [string]$User, [string]$remote, [string]$Port = 22, [string]$IAMRole, [string]$Region, [string]$DefaultInstanceName)
{
    Write-Verbose "SSMInstallLinuxAgent:  Key=$Key, User=$User, Remote=$remote, Port=$Port, IAM Role=$IAMRole, SSMRegion=$Region, DefaultInstanceName=$DefaultInstanceName"
    $global:code = New-SSMActivation -DefaultInstanceName $DefaultInstanceName -IamRole $IAMRole -RegistrationLimit 1 –Region $Region

    $installScript = @"
    mkdir /tmp/ssm
    sudo curl https://amazon-ssm-$region.s3.amazonaws.com/latest/debian_amd64/amazon-ssm-agent.deb -o /tmp/ssm/amazon-ssm-agent.deb
    sudo dpkg -i /tmp/ssm/amazon-ssm-agent.deb
    sudo stop amazon-ssm-agent
    sudo amazon-ssm-agent -register -code "$($code.ActivationCode)" -id "$($code.ActivationId)" -region "$region" 
    sudo start amazon-ssm-agent
"@
    $output = Invoke-SSHCommand -key $key -user $user -remote $remote -port $port -cmd $installScript
    Write-Verbose "sshoutput:`n$output"
   
    $filter = @{Key='ActivationIds'; ValueSet=$code.ActivationId}
    $InstanceId = (Get-SSMInstanceInformation -InstanceInformationFilterList $filter -Region $Region).InstanceId

    Remove-SSMActivation $code.ActivationId -Force -Region $Region

    $cmd = { 
        (Get-SSMInstanceInformation -InstanceInformationFilterList @{ Key='InstanceIds'; ValueSet=$instanceid}).Count -eq 1
    }
    $null = Invoke-PSUtilWait $cmd 'Instance Registration' 150

    $instanceId
}