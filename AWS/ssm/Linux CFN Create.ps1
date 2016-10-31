param ($Name = "ssm", 
        $InstanceType = 't2.micro',
        $ImagePrefix='amzn-ami-hvm-*gp2', 
        $keyFile = 'c:\keys\test.pem',
        $InstanceCount=2,
        $Region = (Get-PSUtilDefaultIfNull -value (Get-DefaultAWSRegion) -defaultValue 'us-east-1'))

Set-DefaultAWSRegion $Regionn

$KeyPairName = 'test'
$RoleName = 'test'
$securityGroup = @((Get-EC2SecurityGroup | ? GroupName -eq 'test').GroupId)
if (Get-EC2SecurityGroup | ? GroupName -eq 'corp') {
    $securityGroup += (Get-EC2SecurityGroup | ? GroupName -eq 'corp').GroupId
}

$image = Get-EC2Image -Filters @{Name = "name"; Values = "$imageprefix*"} | sort -Property CreationDate -Descending | select -First 1

$userdata = @'
#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

sudo yum -y install amazon-ssm-agent
sudo start amazon-ssm-agent
'@.Replace("`r",'')
$userdataBase64Encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($userdata))

$cnfTemplate = @"
{
    "AWSTemplateFormatVersion" : "2010-09-09",
    "Resources" : {
           "launchConfig" : {
           "Type" : "AWS::AutoScaling::LaunchConfiguration",
           "Properties" : {
	  	        "ImageId" : "$($image.ImageId)",
	  	        "InstanceType" : "t2.micro",
		        "IamInstanceProfile" : "$RoleName",
		        "KeyName" : "$KeyPairName",
                "UserData": "$userdataBase64Encoded"
           }
        },
        "asg" : {
            "Type" : "AWS::AutoScaling::AutoScalingGroup",
            "Properties" : {
                "LaunchConfigurationName" : { "Ref" : "launchConfig" },
                "AvailabilityZones" : { "Fn::GetAZs" : ""},
                "MinSize" : "$InstanceCount",
                "MaxSize" : "$InstanceCount",
                 "Tags" : [{
                          "Key"   : "Name",
                          "Value" : "$Name",
                          "PropagateAtLaunch" : "true"
                        }]
            }
        }
    }
}
"@


if (Get-CFNStack | ? StackName -eq $Name) {
    Write-Verbose "Removing CFN Stack $Name"
    Remove-CFNStack -StackName $Name -Force

    $cmd = { $stack = Get-CFNStack | ? StackName -eq $Name; -not $stack}

    $null = Invoke-PSUtilWait -Cmd $cmd -Message "Remove Stack $Name" -RetrySeconds 300
}


$stackId = New-CFNStack -StackName $Name -TemplateBody $cnfTemplate
Write-Verbose "CFN StackId=$stackId"


$cmd = { $stack = Get-CFNStack -StackName $Name; Write-Verbose "CFN Stack $Name Status=$($stack.StackStatus)"; $stack.StackStatus -like '*_COMPLETE'}
$null = Invoke-PSUtilWait -Cmd $cmd -Message 'CFN Stack' -RetrySeconds 300

$instances = Get-WinEC2Instance $Name -DesiredState 'running'
foreach ($instance in $instances) {
    $cmd = { (Get-SSMInstanceInformation -InstanceInformationFilterList @{ Key='InstanceIds'; ValueSet=$instance.InstanceId}).Count -eq 1}
    $null = Invoke-PSUtilWait $cmd 'Instance Registration' $Timeout
}

return

<#
$cnfTemplate = @"
{
  "AWSTemplateFormatVersion" : "2010-09-09",
  "Resources" : {
       "$Name" : {
  	        "Type" : "AWS::EC2::Instance",
   	        "Properties" : {
	  	        "ImageId" : "$($image.ImageId)",
	  	        "InstanceType" : "t2.micro",
		        "IamInstanceProfile" : "$RoleName",
		        "NetworkInterfaces" : [ {
			        "DeviceIndex" : "0",
			        "AssociatePublicIpAddress" : "true",
                    "GroupSet" : $($securityGroup | ConvertTo-Json)
		        } ],
		        "KeyName" : "$KeyPairName",
                 "Tags" : [{
                          "Key"   : "Name",
                          "Value" : "$Name"
                        }],
                 "UserData": "$userdataBase64Encoded"
	        }
       }
    }
}
"@


{
  "AWSTemplateFormatVersion" : "2010-09-09",
  "Resources" : {
    "myEC2" : {
  	"Type" : "AWS::EC2::Instance",
   	"Properties" : {
	  	"ImageId" : "ami-e3fcb686",
	  	"InstanceType" : "t2.micro",
		"SsmAssociations" : [ {
			"DocumentName" : {"Ref" : "document"},
			"AssociationParameters" : [
				{ "Key" : "directoryId", "Value" : ["d-xxxx"] }
			]
		} ]
	}
    },

    "document" : {
	"Type" : "AWS::SSM::Document",
  	"Properties" : {
		"Content" : {
    			"schemaVersion":"1.2",
    			"description":"Join your instances to an AWS Directory Service domain.",
    			"parameters":{
        			"directoryId":{
            				"type":"String",
            				"description":"(Required) The ID of the AWS Directory Service directory."
        			},
    			},
    			"runtimeConfig":{
        			"aws:domainJoin":{
            				"properties":{
                				"directoryId":"{{ directoryId }}"
            				}
        			}
    			}
		}
	}
    }
  }
}
#>