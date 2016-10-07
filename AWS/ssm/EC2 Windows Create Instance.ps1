# You should define before running this script.
#    $name - Name identifies logfile and test name in results
#            When running in parallel, name maps to unique ID.
#            Some thing like '0', '1', etc when running in parallel
#     $obj - This is a global dictionary, used to pass output values
#            (e.g.) report the metrics back, or pass output values that will be input to subsequent functions

param ($Name = 'ssm-windows',
        $InstanceType = 't2.micro',
        $ImagePrefix='Windows_Server-2012-R2_RTM-English-64Bit-Base-20',
        $Region = 'us-east-1'
        )

Set-DefaultAWSRegion $Region
. "$PSScriptRoot\Common Setup.ps1"

Remove-WinEC2Instance $Name -NoWait

$securityGroup = @('test')
if (Get-EC2SecurityGroup -GroupName 'corp') {
    $securityGroup += 'corp'
}

#Create Instance
Write-Verbose 'Creating EC2 Windows Instance.'
$global:instance = New-WinEC2Instance -Name $Name -InstanceType $InstanceType `
                        -ImagePrefix $ImagePrefix -SSMHeartBeat `
                        -IamRoleName 'test' -SecurityGroupName $securityGroup -KeyPairName 'test'

$obj.'InstanceType' = $Instance.Instance.InstanceType
$Obj.'InstanceId' = $instance.InstanceId
$Obj.'ImageName' = (get-ec2image $instance.Instance.ImageId).Name
$obj.'PublicIpAddress' = $instance.PublicIpAddress
$obj.'RemoteTime' = $instance.Time.Remote
$obj.'SSMHeartBeat' = $instance.Time.SSMHeartBeat

#Run Command
Write-Verbose 'Run Command on EC2 Windows Instance'
$startTime = Get-Date
$command = SSMRunCommand  -InstanceIds $obj.'InstanceId' -SleepTimeInMilliSeconds 1000 `
    -Parameters @{commands='ipconfig'}
SSMDumpOutput $command

$obj.'CommandId' = $command
$obj.'RunCommandTime' = (Get-Date) - $startTime

<#
#Install Onprem Agent
Write-Verbose 'Install onprem agent on EC2 Windows Instance'
$data = Get-WinEC2Password $obj.'InstanceId'
$secpasswd = ConvertTo-SecureString $data.Password -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ("Administrator", $secpasswd)
$connectionUri = "http://$($obj.'PublicIpAddress'):80/"

$obj.'ActivationId' =  SSMInstallAgent -ConnectionUri $connectionUri -Credential $cred -Region $region -DefaultInstanceName $Name

#Onprem Run Command
Write-Verbose 'Onprem Run Command on EC2 Windows Instance'
$filter = @{Key='ActivationIds'; ValueSet=$Obj.'ActivationId'}
$mi = (Get-SSMInstanceInformation -InstanceInformationFilterList $filter).InstanceId

$startTime = Get-Date
$command = SSMRunCommand -InstanceIds $mi -SleepTimeInMilliSeconds 1000 `
    -Parameters @{commands='ipconfig'}

$obj.'OnpremCommandId' = $command
$obj.'OnpremRunCommandTime' = (Get-Date) - $startTime
SSMDumpOutput $command
#>
