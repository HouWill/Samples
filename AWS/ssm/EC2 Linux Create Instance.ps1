# You should define before running this script.
#    $name - Name identifies logfile and test name in results
#            When running in parallel, name maps to unique ID.
#            Some thing like '0', '1', etc when running in parallel

param ($Name = 'ssmlinux', 
        $InstanceType = 't2.micro',
        #$ImagePrefix= 'ubuntu/images/hvm-ssd/ubuntu-xenial-16*', 
        $ImagePrefix='amzn-ami-hvm-*gp2', 
        $keyFile = 'c:\keys\test.pem',
        $InstanceCount=2,
        $Region = (Get-PSUtilDefaultIfNull -value (Get-DefaultAWSRegion) -defaultValue 'us-east-1'))

Set-DefaultAWSRegion $Region

Write-Verbose "EC2 Linux Create Instance Name=$Namme, ImagePrefix=$ImagePrefix, keyFile=$keyFile, InstanceCount=$InstanceCount, Region=$Region"
SSMSetTitle "$Name, EC2"

. "$PSScriptRoot\EC2 Terminate Instance.ps1" $Name

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


    $userdata = @"
#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

if [ -f /etc/debian_version ]; then
    echo "Debian"
    #curl https://amazon-ssm-us-east-1.s3.amazonaws.com/latest/debian_amd64/amazon-ssm-agent.deb -o amazon-ssm-agent.deb
    apt install awscli -y
    aws s3 --region $Region cp s3://sivaiadbucket/Agent/amazon-ssm-agent-2.0.512.0-1.deb amazon-ssm-agent.deb
    dpkg -i amazon-ssm-agent.deb

    aws s3 cp s3://sivaiadbucket/Agent/seelog.xml /etc/amazon/ssm/seelog.xml
    $(
        if ($endpoint -like '*sonic*') {
            "aws s3 --region $Region cp s3://sivaiadbucket/Agent/amazon-ssm-agent-gamma.json /etc/amazon/ssm/amazon-ssm-agent.json"
        } else {
            "aws s3 --region $Region cp s3://sivaiadbucket/Agent/amazon-ssm-agent.json /etc/amazon/ssm/amazon-ssm-agent.json"
        }
    )
    service amazon-ssm-agent restart
else
    echo "Amazon Linux or Redhat"
    
    aws s3 --region $Region cp s3://sivaiadbucket/Agent/amazon-ssm-agent-2.0.533.0-1.x86_64.rpm amazon-ssm-agent.rpm
    #aws s3 --region $Region cp s3://sivaiadbucket/Agent/amazon-ssm-agent.rpm amazon-ssm-agent.rpm
    yum install -y amazon-ssm-agent.rpm

    aws s3 cp s3://sivaiadbucket/Agent/seelog.xml /etc/amazon/ssm/seelog.xml
   # (
   #     if ($endpoint -like '*sonic*') {
   #         "aws s3 --region $Region cp s3://sivaiadbucket/Agent/amazon-ssm-agent-gamma.json /etc/amazon/ssm/amazon-ssm-agent.json"
   #     }
   # )
    restart amazon-ssm-agent
fi

"@.Replace("`r",'')

    $userdata = @"
#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

if [ -f /etc/debian_version ]; then
    echo "Debian"
    curl https://amazon-ssm-$Region.s3.amazonaws.com/latest/debian_amd64/amazon-ssm-agent.deb -o amazon-ssm-agent.deb
    dpkg -i amazon-ssm-agent.deb
else
    echo "Amazon Linux or Redhat"
    curl https://amazon-ssm-$Region.s3.amazonaws.com/latest/linux_amd64/amazon-ssm-agent.rpm -o amazon-ssm-agent.rpm
    yum install -y amazon-ssm-agent.rpm
fi

"@.Replace("`r",'')

$securityGroup = @('test')
if (Get-EC2SecurityGroup | ? GroupName -eq 'corp') {
    $securityGroup += 'corp'
}

Write-Verbose 'Creating EC2 Windows Instance.'
$instances = New-WinEC2Instance -Name $Name -InstanceType $InstanceType `
                        -ImagePrefix $ImagePrefix -Linux `
                        -IamRoleName 'test' -SecurityGroupName $securityGroup -KeyPairName 'test' `
                        -UserData $userdata -SSMHeartBeat -InstanceCount $InstanceCount


$obj = @{}
$obj.'InstanceType' = $instances[0].Instance.InstanceType
$InstanceIds = $Obj.'InstanceIds' = $instances.InstanceId
$Obj.'ImageName' = (get-ec2image $instances[0].Instance.ImageId).Name
$obj.'PublicIpAddress' = $instances.PublicIpAddress
$obj.'SSMHeartBeatTime' = $instances[0].Time.SSMHeartBeat

<#
foreach ($instance in $instances) {
    if ($instance.PlatformName -eq 'Ubuntu') {
        $user = 'ubuntu'
    } else {
        $user = 'ec2-user'
    }
    Invoke-PSUtilRetryOnError {$output = Invoke-PsUtilSSHCommand -key $keyFile -user $user -remote $Instance.PublicIpAddress -port 22 -cmd "ps"} -retryCount 3
    Write-Verbose "SSH Output for InstanceId=$($instance.InstanceId), PublicIpAddress=$($Instance.PublicIpAddress):`n$output"
}
#>

return $obj

#sudo apt-get install upstart -y