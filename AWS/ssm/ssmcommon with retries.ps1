Set-DefaultAWSRegion 'us-east-1'
$VerbosePreference='Continue'

function SSMWait ([ScriptBlock] $Cmd, [string] $Message, [int] $RetrySeconds)
{
    $msg = "Waiting for $Message to succeed"
    $t1 = Get-Date
    Write-Verbose "$msg in $RetrySeconds seconds"
    while ($true)
    {
        $t2 = Get-Date
        try
        {
            $result = & $cmd 2>$null | select -Last 1 
            if ($? -and $result)
            {
                Write-Verbose "Succeeded $Message in $([int]($t2-$t1).TotalSeconds) Seconds, Result=$result"
                break;
            }
        }
        catch
        {
        }
        $t = [int]($t2 - $t1).TotalSeconds
        if ($t -gt $RetrySeconds)
        {
            throw "Timeout - $Message after $RetrySeconds seconds, Current result=$result"
            break
        }
        Write-Verbose "$msg ($t/$RetrySeconds) Seconds."
        Sleep -Seconds 5
    }
}

function SSMGetAssociation ($instance)
{
    $association = Get-SSMAssociationList -AssociationFilterList @{Key='InstanceId'; Value=$instance.instanceid}
    if ($association)
    {
        Get-SSMAssociation -InstanceId $association.InstanceId -Name $association.Name
    }
}

function SSMCreateAssociation ($instance, [string]$name)
{
    $instanceId = $instance.InstanceId
    Write-Verbose "Creating Association InstanceId=$InstanceId, Name=$Name"
    $null = New-SSMAssociation -InstanceId $instanceid -Name $name
    $cmd = {@(Get-SSMAssociationList -AssociationFilterList @{Key='InstanceId'; Value=$instanceid}).Count -gt 0}
    $null = SSMWait $cmd -Message 'Create Association' -RetrySeconds 30
}

function SSMDeleteAssociation ($instance)
{
    $instanceId = $instance.InstanceId
    $association = Get-SSMAssociationList -AssociationFilterList @{Key='InstanceId'; Value=$instanceid}
    if ($association)
    {
        Write-Verbose "Deleting Association InstanceId=$($association.InstanceId) Name=$($association.Name)"
        Remove-SSMAssociation -InstanceId $association.InstanceId -Name $association.Name -Force
        $cmd = {@(Get-SSMAssociationList -AssociationFilterList @{Key='InstanceId'; Value=$instanceid}).Count -eq 0}
        $null = SSMWait $cmd -Message 'Remove Association' -RetrySeconds 30
    }
    else
    {
        Write-Verbose "No Association found for $instanceid to delete"
    }
}

function SSMCreateDocument ([string]$content, [string]$name)
{
    Write-Verbose "Creating Document Name=$name"
    $null = New-SSMDocument -Content $content -Name $name
    $cmd = {@(Get-SSMDocumentList | Where {$_.Name -eq $name}).Count -gt 0}
    $null = SSMWait $cmd 'Create Document' -RetrySeconds 30
}

function SSMDeleteDocument ([string]$name)
{
    $document = Get-SSMDocumentList -DocumentFilterList @{Key='Name'; Value=$name}
    if ($document)
    {
        Write-Verbose "Deleting Document Name=$name"
        Remove-SSMDocument -Name $name -Force
        $cmd = {@(Get-SSMDocumentList | Where {$_.Name -eq $name}).Count -eq 0}
        $null = SSMWait $cmd 'Remove Document' -RetrySeconds 30
    }
    else
    {
        Write-Verbose "Document Name=$name not found"
    }
}

function SSMGetLogs ($instance, [string]$log = 'ssm.log')
{
    Write-Verbose "Log file $log"
    $cmd = {
        Get-EventLog -LogName Ec2ConfigService |
        % { $_.Message.trim() } | 
        sort 
     }
    icm $instance.PublicIpAddress $cmd -Credential $cred -Port 80 > $log
    notepad $log
}

function SSMAssociate ($instance, [string]$doc, $RetrySeconds = 150)
{
    $instanceId = $instance.InstanceId
    $log = 'ssm.log'
    del $log -ea 0

    icm $instance.PublicIpAddress {Clear-EventLog -LogName Ec2ConfigService} -Credential $cred -Port 80

    $name = 'doc-' + [Guid]::NewGuid()
    Write-Verbose "Document Name=$name"
    $null = SSMCreateDocument -Content $doc -name $name
    $null = SSMCreateAssociation -Instance $instance -Name $name
    try
    {
        $cmd = {Get-Service EC2Config | Stop-Service -Force}
        icm $instance.PublicIpAddress $cmd -Credential $cred -Port 80
        $cmd = {
            (Get-Service EC2Config -ComputerName $instance.PublicIpAddress |
                where { $_.Status -eq 'Stopped' }).Count -eq 1
        }
        $cmd = {
           $cmd1 = {Get-Service EC2Config | where {$_.Status -eq 'Stopped'}}
           icm $instance.PublicIpAddress $cmd1 -Credential $cred -Port 80
        }
        $null = SSMWait $cmd -Message 'Stop EC2Config' -RetrySeconds 60

        $cmd = {Get-Service EC2Config | Start-Service}
        icm $instance.PublicIpAddress $cmd -Credential $cred -Port 80

        $cmd = {
           $cmd1 = {Get-Service EC2Config | where {$_.Status -eq 'Running'}}
           icm $instance.PublicIpAddress $cmd1 -Credential $cred -Port 80
        }
        $null = SSMWait $cmd -Message 'Start EC2Config' -RetrySeconds 60
    
        $cmd = {
            do
            {
                $status1 = (Get-SSMAssociation -InstanceId $instanceid -Name $name).Status
                Write-host "Status1=$($status1.Name), Date=$($status1.Date), Name=$name, Message=$($status1.Message)"
                Sleep 10
                $status2 = (Get-SSMAssociation -InstanceId $instanceid -Name $name).Status
                Write-host "Status2=$($status2.Name), Date=$($status1.Date), Name=$name, Message=$($status2.Message)"
            } while ($status1.Name -ne $status2.Name)
            $status1.Name -eq 'Success' -or $status1.Name -eq 'Failed'
        }
        $null = SSMWait $cmd -Message 'Converge Association' -RetrySeconds $RetrySeconds

        $a = (Get-SSMAssociation -InstanceId $instanceid -Name $name).Status

        $a | fl *
        if ($a.Name -ne 'Success')
        {
            throw 'SSM Failed'
        }
    }
    catch
    {
        $_
        Write-Verbose "Caught Exception"
        SSMGetLogs $instance $log
        throw $_
    }
    SSMDeleteDocument $name
    SSMDeleteAssociation $instance
}

