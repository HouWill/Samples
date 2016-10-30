# You should define before running this script.
#    $name - Name identifies logfile and test name in results
#            When running in parallel, name maps to unique ID.
#            Some thing like '0', '1', etc when running in parallel


param ($Name = 'ssm-windows',
        $Region = (Get-PSUtilDefaultIfNull -value (Get-DefaultAWSRegion) -defaultValue 'us-east-1'))

Write-Verbose "Windows Run Command Name=$Name, Region=$Region"
Set-DefaultAWSRegion $Region

$instance = Get-WinEC2Instance $Name -DesiredState 'running'
$instanceId = $instance.InstanceId
Write-Verbose "Name=$Name InstanceId=$instanceId"


#Run Command
Write-Verbose 'InstallPowerShellModule'

$dir = $PSScriptRoot

Compress-Archive -Path "$dir\PSDemo\*" -DestinationPath "$dir\PSDemo.zip" -Force

$s3Bucket = (Get-SSMS3Bucket).BucketName
$s3ZipKey = "SSMOutput/$Name/PSDemo.zip"
$s3KeyPrefix = 'SSMOutput'

write-S3Object -BucketName $S3Bucket -key $s3ZipKey -File $dir\PSDemo.zip

del $dir\PSDemo.zip 

$startTime = Get-Date
$command = SSMRunCommand `
    -InstanceIds $instanceId `
    -DocumentName 'AWS-InstallPowerShellModule' `
    -SleepTimeInMilliSeconds 5000 `
    -Parameters @{
        source="https://s3.amazonaws.com/$S3Bucket/$s3ZipKey"
        commands=@('Test1')
     } `
     -Outputs3BucketName $s3Bucket -Outputs3KeyPrefix $s3KeyPrefix

$obj = @{}
$obj.'CommandId' = $command
$obj.'RunCommandTime' = (Get-Date) - $startTime

if ($command.OutputS3BucketName -ne $s3Bucket) {
    throw "OutputS3BucketName did not match. Actual Bucket=$($command.OutputS3BucketName), Expected=$s3Bucket, CommandId=$($command.CommandId)"
}
if ($command.OutputS3KeyPrefix -ne $s3KeyPrefix) {
    throw "OutputS3KeyPrefix did not match. Actual OutputS3KeyPrefix=$($command.OutputS3KeyPrefix), Expected=$s3KeyPrefix, CommandId=$($command.CommandId)"
}

Test-SSMOuput $command -ExpectedMinLength 38 -ExpectedMaxLength 38
$null = Remove-S3Object -BucketName $S3Bucket -Key $s3ZipKey -Force

return $obj