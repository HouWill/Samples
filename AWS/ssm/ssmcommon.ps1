Set-DefaultAWSRegion 'us-east-1'
$VerbosePreference='Continue'

function SSMWait (
    [ScriptBlock] $Cmd, 
    [string] $Message, 
    [int] $RetrySeconds)
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
                Write-Verbose("Succeeded $Message in " + `
                    "$([int]($t2-$t1).TotalSeconds) Seconds, Result=$result")
                break;
            }
        }
        catch
        {
        }
        $t = [int]($t2 - $t1).TotalSeconds
        if ($t -gt $RetrySeconds)
        {
            throw "Timeout - $Message after $RetrySeconds seconds, " +  `
                "Current result=$result"
            break
        }
        Write-Verbose "$msg ($t/$RetrySeconds) Seconds."
        Sleep -Seconds 5
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
