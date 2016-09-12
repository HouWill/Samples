# You should define before running this script.
#    $name - You can create some thing like '1', '2', '3' etc for each session
param ([string]$name = 'perf0', 
        $DefaultRegion = 'us-east-1', 
        $S3Bucket='sivaiadbucket')

#break into debugger, incase of error
trap { $Debugger = 'break'} #This stops execution on any exception
$ErrorActionPreference = 'Stop'
$null = Set-PSBreakpoint -Variable Debugger -Mode Write

#Start-Transcript -Path "Output\$name.log"

Write-Verbose "Name=$name"
cd $PSScriptRoot

Import-Module -Global WinEC2 -Force 4>$null
Import-Module -Global PSTest -Force 4>$null
. ..\ssm\ssmcommon.ps1
$VerbosePrefence = 'Continue'

Set-DefaultAWSRegion $DefaultRegion

function ginfo ([string]$tag = $name)
{
    $instance = Get-WinEC2Instance $tag
    $instance | Add-Member -NotePropertyName 'ImageName' -NotePropertyValue (Get-EC2Image $instance.ImageId).Name
    $instance 

    New-EC2Tag -ResourceId $instance.InstanceId -Tag @{Key='Name'; Value="save-$name"}

    ''
    Get-PsUtilMultiLineStringFromObject $obj

    ping $instance.PublicIPAddress

    #Stop-Transcript
}

function Cleanup ()
{
    Get-PSSession | Remove-PSSession -ea 0
    Invoke-PSUtilIgnoreError {Remove-WinEC2Instance $name -NoWait}
}

function CreateInstance ()
{
    $parameters = @{
        Name=$obj.Name
        InstanceType=$obj.InstanceType
        ImagePrefix=$obj.ImagePrefix
        AmiId=$obj.AmiId
#       Placement_AvailabilityZone='us-east-1d'
        DontCleanUp=$true
        Timeout=$obj.Timeout
        IamRoleName=$obj.IamRoleName
        AdditionalInfo=$obj.AdditionalInfo
        SecurityGroupName=$obj.SecurityGroupName
        KeyPairName=$obj.KeyPairName
    }
    
    $global:instance = New-WinEC2Instance @parameters
    $obj.InstanceId = $instance.Instanceid
    $obj.RunningTime = $instance.Time.Running
    $obj.PingTime = $instance.Time.Ping
    $obj.PasswordTime = $instance.Time.Password
    $obj.RemoteTime = $instance.Time.Remote
    $obj.AZ = $instance.Instance.Placement.AvailabilityZone
    $obj.EbsOptimized = $instance.Instance.EbsOptimized
}

function RunCommand ()
{
    $startTime = Get-Date
    $command = SSMRunCommand `
        -InstanceIds $obj.InstanceId `
        -SleepTimeInMilliSeconds 1000 `
        -Parameters @{
            commands=@(
             'ipconfig'
            )
         }

    $obj.RunCommandTime = (Get-Date) - $startTime
}

function Reboot ()
{
    $startTime = Get-Date

    $keyfile = Get-WinEC2KeyFile $obj.KeyPairName
    $Password = Get-EC2PasswordData -InstanceId $obj.InstanceId -PemFile $keyfile -Decrypt
    $securepassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $creds = New-Object System.Management.Automation.PSCredential ("Administrator", $securepassword)

    ReStart-WinEC2Instance -NameOrInstanceIds $obj.InstanceId -Credential $creds
    $obj.RestartTime = (Get-Date) - $startTime
}

function StopStart ()
{
    $startTime = Get-Date

    $keyfile = Get-WinEC2KeyFile $obj.KeyPairName
    $Password = Get-EC2PasswordData -InstanceId $obj.InstanceId -PemFile $keyfile -Decrypt
    $securepassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $creds = New-Object System.Management.Automation.PSCredential ("Administrator", $securepassword)

    Stop-WinEC2Instance -NameOrInstanceIds $obj.InstanceId 
    $obj.StopTime = (Get-Date) - $startTime

    $startTime2 = Get-Date
    Start-WinEC2Instance -NameOrInstanceIds $obj.InstanceId -Credential $creds
    $obj.StartStartTime = (Get-Date) - $startTime2
    $obj.StopStartTime = (Get-Date) - $startTime
}


Invoke-PsTestRandomLoop -Name $name `
    -Main {
        Cleanup 
        CreateInstance
        RunCommand
        Reboot
        StopStart
        Cleanup
     } `
    -Parameters @{ 
        #InstanceId=(Get-WinEC2Instance $name).InstanceId
        Timeout=1500
        SecurityGroupName='test'
        KeyPairName='test'
        IamRoleName='test'
        InstanceType = @('t2.micro'
                        #'t2.micro','t2.small','t2.medium', 't2.large'
                        #'m4.large','m4.xlarge'
                        #'m3.medium', 'm3.large','m3.xlarge',
                        #'c4.large','c4.xlarge',
                        #'r3.large','r3.xlarge'
                )
        #AmiId = 'ami-b68819de' 
        ImagePrefix = 'Windows_Server-2012-R2_RTM-English-64Bit-Base-20'
    } `
    -OnError {ginfo} `
    -ContinueOnError `
    -MaxCount 1
#Stop-Transcript