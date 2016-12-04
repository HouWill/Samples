# You should define before running this script.
#    $name - Name identifies logfile and test name in results
#            When running in parallel, name maps to unique ID.
#            Some thing like '0', '1', etc when running in parallel
#     $obj - This is a global dictionary, used to pass output values
#            (e.g.) report the metrics back, or pass output values that will be input to subsequent functions

param ($Name = 'ssmwindows',
        $InstanceType = 't2.micro',
        #$ImagePrefix='Windows_Server-2012-R2_RTM-English-64Bit-Base-20',
        $ImagePrefix='Windows_Server-2016-English-Full-Base-20',
        $Region = (Get-PSUtilDefaultIfNull -value (Get-DefaultAWSRegion) -defaultValue 'us-east-1')
        )
Write-Verbose "Windows Create Instance Name=$Name, InstanceType=$InstanceType, ImagePrefix=$ImagePrefix, Region=$Region"
Set-DefaultAWSRegion $Region

SSMSetTitle $Name

Remove-WinEC2Instance $Name -NoWait

$securityGroup = @('test')
if (Get-EC2SecurityGroup | ? GroupName -eq 'corp') {
    $securityGroup += 'corp'
}

#Create Instance
Write-Verbose 'Creating EC2 Windows Instance.'
$global:instance = New-WinEC2Instance -Name $Name -InstanceType $InstanceType `
                        -ImagePrefix $ImagePrefix -SSMHeartBeat `
                        -IamRoleName 'test' -SecurityGroupName $securityGroup -KeyPairName 'test'

$obj = @{}
$obj.'InstanceType' = $Instance.Instance.InstanceType
$global:InstanceIds = $Obj.'InstanceIds' = $instance.InstanceId
$Obj.'ImageName' = (get-ec2image $instance.Instance.ImageId).Name
$obj.'PublicIpAddress' = $instance.PublicIpAddress
$obj.'RemoteTime' = $instance.Time.Remote
$obj.'SSMHeartBeat' = $instance.Time.SSMHeartBeat

return $obj