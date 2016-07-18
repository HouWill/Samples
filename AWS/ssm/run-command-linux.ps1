param($ImageName = 'amzn-ami-hvm-*gp2')

Write-Host "***********************************" -ForegroundColor Yellow
Write-Host "ImangeName=$ImageName" -ForegroundColor Yellow
Write-Host "***********************************" -ForegroundColor Yellow

Set-DefaultAWSRegion 'us-east-1'
#Set-DefaultAWSRegion 'us-west-2'
$VerbosePreference='Continue'
trap { break } #This stops execution on any exception
$ErrorActionPreference = 'Stop'

cd $PSScriptRoot
. .\ssmcommon.ps1

$index = '1'
if ($psISE -ne $null)
{
    #Role name is suffixed with the index corresponding to the ISE tab
    #Ensures to run multiple scripts concurrently without conflict.
    $index = $psISE.CurrentPowerShellTab.DisplayName.Split(' ')[1]
}
$instanceName = "ssm-demo-$index"

Write-Host "`nCreate Role winec2role if not present" -ForegroundColor Yellow
SSMCreateRole

Write-Host "`nCreate Keypair winec2keypair if not present and save the in c:\keys" -ForegroundColor Yellow
SSMCreateKeypair

Write-Host "`nCreate SecurityGroup winec2securitygroup if not present" -ForegroundColor Yellow
SSMCreateSecurityGroup 

Write-Host "`nCreate a new instance and name it as $instanceName" -ForegroundColor Yellow
$instanceId = SSMCreateLinuxInstance -Tag $instanceName -ImageName $ImageName -InstanceCount 3
#$instanceId = SSMCreateLinuxInstance -Tag $instanceName -ImageName 'ubuntu/images/hvm-ssd/ubuntu-*-14.*' -InstanceCount 3

$script = @'
ifconfig
'@.Replace("`r",'')

Write-Host "`nAWS-RunShellScript: Excute shell script" -ForegroundColor Yellow
$command = SSMRunCommand `
    -InstanceIds $instanceId `
    -DocumentName 'AWS-RunShellScript' `
    -Parameters @{
        commands=$script
     } `
    -Outputs3BucketName 'sivaiadbucket'

#Read-Host 'AWS-RunShellScript: completed'

#Cleanup
Write-Host "`nTerminating instance" -ForegroundColor Yellow
SSMRemoveInstance $instanceName

#SSMRemoveRole

#SSMRemoveKeypair

#SSMRemoveSecurityGroup 
