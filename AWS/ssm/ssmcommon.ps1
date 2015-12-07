$VerbosePreference='Continue'

function SSMCreateKeypair (
        [string]$KeyName = 'ssm-demo-key',
        [string]$KeyFile = "c:\keys\$keyName.$((Get-DefaultAWSRegion).Region).pem"
    )
{
    if (Get-EC2KeyPair  | ? { $_.KeyName -eq $keyName }) { 
        Write-Verbose "Skipping as keypair ($keyName) already present." 
        return
    }
    Write-Verbose "Create keypair=$keypair, keyfile=$keyfile"
    $keypair = New-EC2KeyPair -KeyName $keyName
    "$($keypair.KeyMaterial)" | Out-File -encoding ascii -filepath $keyfile
}

function SSMRemoveKeypair (
        [string]$KeyName = 'ssm-demo-key',
        [string]$KeyFile = "c:\keys\$keyName.$((Get-DefaultAWSRegion).Region).pem"
    )
{
    #delete keypair
    del $keyfile -ea 0
    Remove-EC2KeyPair -KeyName $keyName -Force
    Write-Verbose "Removed keypair=$keypair, keyfile=$keyfile"
}

function SSMCreateInstance (
        [string]$ImageName = 'WINDOWS_2012R2_BASE',
        [string]$SecurityGroupName = 'ssm-demo-sg',
        [string]$InstanceType = 'm4.large',
        [string]$Tag = 'ssm-demo',
        [string]$KeyName = 'ssm-demo-key',
        [string]$KeyFile = "c:\keys\$keyName.$((Get-DefaultAWSRegion).Region).pem",
        [string]$RoleName = 'ssm-demo-role'
    )
{
    $filter1 = @{Name='tag:Name';Value=$Tag}
    $filter2 = @{Name='instance-state-name';Values=@('running','pending','stopped')}
    $instance = Get-EC2Instance -Filter @($filter1, $filter2)
    if ($instance) {
        $instanceId = $instance.Instances[0].InstanceId
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
    $instance = (New-EC2Instance -ImageId $image.ImageId `
                    -InstanceProfile_Id $RoleName `
                    -AssociatePublicIp $true `
                    -SecurityGroupId $securityGroupId `
                    -KeyName $keyName `
                    -UserData $userdataBase64Encoded `
                    -InstanceType $InstanceType).Instances[0]

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

    #update the instance to get the public IP Address
    $instance = (Get-EC2Instance $instance.InstanceId).Instances[0]

    #Wait for remote PS connection
    $cmd = {
        icm $instance.PublicIpAddress {dir c:\} -Credential $creds -Port 80 
    }
    SSMWait $cmd 'Remote Connection' 450

    New-EC2Tag -ResourceId $instance.InstanceId -Tag @{Key='Name'; Value=$Tag}
    $instance.InstanceId
}

function SSMEnter-PSSession (
        [string]$Tag = $instanceName,
        [string]$KeyName = 'ssm-demo-key',
        [string]$KeyFile = "c:\keys\$keyName.$((Get-DefaultAWSRegion).Region).pem"
    )
{
    $instance = (Get-EC2Instance -Filter @{Name='tag:Name';Value=$Tag}).Instances[0]

    $password = Get-EC2PasswordData -InstanceId $instance.InstanceId `
                    -PemFile $keyfile -Decrypt 
    $securepassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $creds = New-Object System.Management.Automation.PSCredential ("Administrator", $securepassword)
    Enter-PSSession $instance.PublicIpAddress -Credential $creds -Port 80 
}

function SSMRemoveInstance (
        [string]$Tag = 'ssm-demo',
        [string]$KeyName = 'ssm-demo-key',
        [string]$KeyFile = "c:\keys\$keyName.$((Get-DefaultAWSRegion).Region).pem"
    )
{
    $filter1 = @{Name='tag:Name';Value=$Tag}
    $filter2 = @{Name='instance-state-name';Values=@('running','pending','stopped')}
    $instance = Get-EC2Instance -Filter @($filter1, $filter2)
    
    if ($instance) {
        $instanceId = $instance.Instances[0].InstanceId

        $null = Stop-EC2Instance -Instance $instanceId -Force -Terminate

        Write-Verbose "Terminated instance $instanceId"
    } else {
        Write-Verbose "Skipping as instance with name=$Tag not found"
    }
}

function SSMCreateSecurityGroup ([string]$SecurityGroupName = 'ssm-demo-sg')
{
    if (Get-EC2SecurityGroup | ? { $_.GroupName -eq $securityGroupName }) {
        Write-Verbose "Skipping as SecurityGroup $securityGroupName already present."
        return;
    }
    #Security group and the instance should be in the same network (VPC)
    $securityGroupId = New-EC2SecurityGroup $securityGroupName  -Description "SSM Demo" -VpcId $subnet.VpcId
    Write-Verbose "Security Group $securityGroupName created"

    $bytes = (Invoke-WebRequest 'http://checkip.amazonaws.com/').Content
    $SourceIPRange = @(([System.Text.Encoding]::Ascii.GetString($bytes).Trim() + "/32"))
    Write-Verbose "$sourceIPRange retreived from checkip.amazonaws.com"

    $fireWallPermissions = @(
        @{IpProtocol = 'tcp'; FromPort = 3389; ToPort = 3389; IpRanges = $SourceIPRange},
        @{IpProtocol = 'tcp'; FromPort = 5985; ToPort = 5986; IpRanges = $SourceIPRange},
        @{IpProtocol = 'tcp'; FromPort = 80; ToPort = 80; IpRanges = $SourceIPRange},
        @{IpProtocol = 'icmp'; FromPort = -1; ToPort = -1; IpRanges = $SourceIPRange}
    )

    Grant-EC2SecurityGroupIngress -GroupId $securityGroupId `
        -IpPermissions $fireWallPermissions
    Write-Verbose 'Granted permissions for ports 3389, 80, 5985'
}

function SSMRemoveSecurityGroup ([string]$SecurityGroupName = 'ssm-demo-sg')
{
    $securityGroupId = (Get-EC2SecurityGroup | `
        ? { $_.GroupName -eq $securityGroupName }).GroupId

    if ($securityGroupId) {
        SSMWait {(Remove-EC2SecurityGroup $securityGroupId -Force) -eq $null} `
                'Delete Security Group' 150
        Write-Verbose "Security Group $securityGroupName removed"
    } else {
        Write-Verbose "Skipping as SecurityGroup $securityGroupName not found"
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
        #$status2 = (Get-SSMCommandInvocation -CommandId $result.CommandId -Details $true).CommandPlugins[0].Status
        ($status1 -ne 'Pending' -and $status1 -ne 'InProgress')
    }

    $null = SSMWait -Cmd $cmd -Message 'Command Execution' -RetrySeconds $Timeout -SleepTimeInMilliSeconds $SleepTimeInMilliSeconds
    
    $command = Get-SSMCommand -CommandId $result.CommandId
    if ($command.Status -ne 'Success') {
        throw "Command $($command.CommandId) did not succeed, Status=$($command.Status)"
    }
    $command
}

function SSMDumpOutput (
        $Command,
        [boolean]$DeleteS3Keys = $true
    )
{
    $commandId = $Command.CommandId
    $bucket = $Command.OutputS3BucketName
    $key = $Command.OutputS3KeyPrefix
    foreach ($instanceId in $Command.InstanceIds) {
        Write-Verbose "InstanceId=$instanceId"

        $invocation = Get-SSMCommandInvocation -InstanceId $instanceId `
                        -CommandId $commandId -Details $true

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
                    if ($s3object.key.EndsWith('stdout.txt')) {
                        cat $tempFile -Raw
                    } elseif ($s3object.key.EndsWith('stderr.txt')) {
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

function SSMCreateRole ([string]$RoleName = 'ssm-demo-role')
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
        "Principal":{"Service":"ec2.amazonaws.com"},
        "Action":"sts:AssumeRole"
      }
    ]
}
"@

    # Define which API actions and resources the application can use 
    # after assuming the role
    $policy = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData",
        "ds:CreateComputer",
        "ec2messages:*",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:PutLogEvents",
        "s3:PutObject",
        "s3:GetObject",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts",
        "s3:ListBucketMultipartUploads",
        "ssm:DescribeAssociation",
        "ssm:ListAssociations",
        "ssm:GetDocument",
        "ssm:UpdateAssociationStatus",
        "ssm:UpdateInstanceInformation",
        "ec2:DescribeInstanceStatus"
      ],
      "Resource": "*"
    }
  ]
}
"@

    $null = New-IAMRole -RoleName $RoleName `
                -AssumeRolePolicyDocument $assumePolicy
    Write-IAMRolePolicy -RoleName $RoleName `
                -PolicyDocument $policy -PolicyName 'ssm'

    #Create instance profile and add the above created role
    $null = New-IAMInstanceProfile -InstanceProfileName $RoleName
    Add-IAMRoleToInstanceProfile -InstanceProfileName $RoleName `
            -RoleName $RoleName
    Write-Verbose "Role $RoleName created" 
}

function SSMRemoveRole ([string]$RoleName = 'ssm-demo-role')
{
    if (!(Get-IAMRoles | ? {$_.RoleName -eq $RoleName})) {
        Write-Verbose "Skipping as role ($RoleName) not found"
        return
    }
    #Remove the instance role and IAM Role
    Remove-IAMRoleFromInstanceProfile -InstanceProfileName $RoleName `
        -RoleName $RoleName -Force
    Remove-IAMInstanceProfile $RoleName -Force
    Remove-IAMRolePolicy $RoleName ssm -Force
    Remove-IAMRole $RoleName -Force
    Write-Verbose "Role $RoleName removed" 
}

function SSMWait (
    [ScriptBlock] $Cmd, 
    [string] $Message, 
    [int] $RetrySeconds,
    [int] $SleepTimeInMilliSeconds = 5000)
{
    $_msg = "Waiting for $Message to succeed"
    $_t1 = Get-Date
    Write-Verbose "$_msg in $RetrySeconds seconds"
    while ($true)
    {
        $_t2 = Get-Date
        try
        {
            $_result = & $Cmd 2>$_null | select -Last 1 
            if ($? -and $_result)
            {
                Write-Verbose("Succeeded $Message in " + `
                    "$_([int]($_t2-$_t1).TotalSeconds) Seconds, Result=$_result")
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
        Write-Verbose "$_msg ($_t/$RetrySeconds) Seconds."
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
