# You should define before running this script.
#    $name - Name identifies logfile and test name in results
#            When running in parallel, name maps to unique ID.
#            Some thing like '0', '1', etc when running in parallel
#     $obj - This is a global dictionary, used to pass output values
#            (e.g.) report the metrics back, or pass output values that will be input to subsequent functions

param ($Name = "ssm-linux", $InstanceType = 't2.micro',
        $ImagePrefix='amzn-ami-hvm-*gp2',$Region = 'us-east-1', $keyFile = 'c:\keys\test.pem')

Set-DefaultAWSRegion $Region
. "$PSScriptRoot\Common Setup.ps1"

Remove-WinEC2Instance $Name -NoWait


#Create Instance
$userdata = @'
#cloud-config
packages:
- amazon-ssm-agent

runcmd:
- start amazon-ssm-agent

'@.Replace("`r",'')

$userdata = @'
#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

sudo yum -y install amazon-ssm-agent
sudo start amazon-ssm-agent
'@.Replace("`r",'')

$securityGroup = @('test')
if (Get-EC2SecurityGroup -GroupName 'corp') {
    $securityGroup += 'corp'
}

Write-Verbose 'Creating EC2 Windows Instance.'
$global:instance = New-WinEC2Instance -Name $Name -InstanceType $InstanceType `
                        -ImagePrefix $ImagePrefix -Linux `
                        -IamRoleName 'test' -SecurityGroupName $securityGroup -KeyPairName 'test' `
                        -UserData $userdata -SSMHeartBeat 

$obj.'InstanceType' = $Instance.Instance.InstanceType
$global:instanceId = $Obj.'InstanceId' = $instance.InstanceId
$Obj.'ImageName' = (get-ec2image $instance.Instance.ImageId).Name
$obj.'PublicIpAddress' = $instance.PublicIpAddress
$obj.'SSMHeartBeat' = $instance.Time.SSMHeartBeat

Invoke-SSHCommand -key $keyFile -user 'ec2-user' -remote $Instance.PublicIpAddress -port 22 -cmd "ps"
