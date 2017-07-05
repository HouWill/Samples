param (
    $Name = (Get-PSUtilDefaultIfNull -value $Name -defaultValue "ssmlinux"), 
    $ParallelIndex,
    $InstanceIds = $InstanceIds,
    $Region = (Get-PSUtilDefaultIfNull -value (Get-DefaultAWSRegion) -defaultValue 'us-east-1')
    )

. $PSScriptRoot\ssmcommon.ps1
Set-DefaultAWSRegion $Region

if ($InstanceIds.Count -eq 0) {
    Write-Verbose "InstanceIds is empty, retreiving instance with Name=$Name"
    $InstanceIds = (Get-WinEC2Instance $Name -DesiredState 'running').InstanceId
}
Write-Verbose "Linux RC Notification: Name=$Name, InstanceId=$instanceIds"

#
#Notification setup
#
Register-IAMRolePolicy -RoleName 'test' -PolicyArn 'arn:aws:iam::aws:policy/AmazonSNSFullAccess'

$parallelName = "$Name$ParallelIndex"

Get-SNSTopic| ? { $_.TopicArn.EndsWith($parallelName) } | Remove-SNSTopic -Force
Write-Verbose "Create SNS Topic $parallelName"
$topic = New-SNSTopic -Name $parallelName
Write-Verbose "Topic=$topic"

Invoke-PSUtilIgnoreError {Get-SQSQueue -QueueNamePrefix $parallelName | Remove-SQSQueue -Force}
Write-Verbose "Create SQS Queue $parallelName"
$sqs = Invoke-PSUtilWait -cmd {New-SQSQueue $parallelName} -Message 'Create SQS' -RetrySeconds 120 # can't be recreated right after delete, need to wait for 60 sec
$sqsArn = (Get-SQSQueueAttribute $sqs -AttributeName 'QueueArn').QueueARN
Write-Verbose "QueueUrl=$sqs, Arn=$sqsArn"

$subscriptionArn = Connect-SNSNotification -Endpoint $sqsArn -Protocol 'sqs' -TopicArn $topic

$policy = @"
{
  "Version": "2012-10-17",
  "Id": "$sqsArn/SQSDefaultPolicy",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "SQS:SendMessage",
      "Resource": "$sqsArn",
      "Condition": {
        "ArnEquals": {
          "aws:SourceArn": "$topic"
        }
      }
    }
  ]
}
"@

Write-Verbose "Set-SQSQueueAttribute QueueUrl=$sqs"
Set-SQSQueueAttribute -QueueUrl $sqs -Attribute @{ Policy = $policy }

$ownerId = (Get-EC2SecurityGroup -GroupNames "default")[0].OwnerId
Add-SQSPermission -Action 'SendMessage' -QueueUrl $sqs -Label 'queue-permission' -AWSAccountId $ownerId 

$role = Get-IAMRole 'test'                                                   

function receiveMessage ($sqs, $expectedCommandId, $expectedDocumententName, $expectedStatus)
{
    for ($i=0; $i -lt 15; $i++) {
        Write-Verbose "receive Message Iteration #$i"
        $message = Receive-SQSMessage -QueueUrl $sqs -WaitTimeInSeconds 5
        if (-not $message) {
            continue
        }
        $json = ConvertFrom-Json (ConvertFrom-Json $message.Body).Message
        Write-Verbose "Received Message: $json, ExpectedCommandId=$expectedCommandId"

        if ($expectedCommandId -ne $json.commandId) {
            Remove-SQSMessage -QueueUrl $sqs -ReceiptHandle $message.ReceiptHandle -Force
            Write-Error "Unexpected commandId, Received CommandId=$($json.commandId), Expected=$expectedCommandId"
            #continue
        }

        if ($expectedCommandId -ne $json.commandId -or $expectedDocumententName -ne $json.documentName -or $expectedStatus -ne $json.status) {
            throw "Did not match with EXPECTED: CommandId=$expectedCommandId, DocumententName=$expectedDocumententName, Status=$expectedStatus"
        }

        Remove-SQSMessage -QueueUrl $sqs -ReceiptHandle $message.ReceiptHandle -Force
        Write-Verbose "Removed Message: CommandId=$($json.commandId), InstanceId=$($json.InstanceId)"
        return
    }
    throw "Receive Message Failed: EXPECTED: CommandId=$expectedCommandId, DocumententName=$expectedDocumententName, Status=$expectedStatus"
}


function queueShouldBeEmpty ($sqs)
{
        $message = Receive-SQSMessage -QueueUrl $sqs -WaitTimeInSeconds 10
        if ($message) {
            $json = ConvertFrom-Json (ConvertFrom-Json $message.Body).Message
            Write-Verbose "Received Message: $json"
            throw "Unexpected message"
        } else {
            Write-Verbose 'Queue is empty as expected'
        }
}



#
#Run Command with invocation notification
#
#Clear-SQSQueue $sqs
for ($i=0; $i -lt 0; $i++) {
    Write-Verbose ''
    Write-Verbose "Invocation Notification: #$i Sending Command ifconfig InstanceId=$InstanceIds"
    $command = Send-SSMCommand -InstanceIds $InstanceIds -DocumentName 'AWS-RunShellScript' -Parameters @{commands='ifconfig'} `
                  -NotificationConfig_NotificationArn $topic `
                  -NotificationConfig_NotificationType Invocation `
                  -NotificationConfig_NotificationEvent @('Success', 'TimedOut', 'Cancelled', 'Failed') `
                  -ServiceRoleArn $role.Arn
    Write-Verbose "#$i Sending Command ifconfig CommandId=$($command.CommandId), InstanceId=$InstanceIds"

    for ($j=0; $j -lt $InstanceIds.Count; $j++) {
        receiveMessage -sqs $sqs -expectedCommandId $command.CommandId -expectedDocumententName 'AWS-RunShellScript' -expectedStatus 'Success'
    }
    queueShouldBeEmpty -sqs $sqs
    Test-SSMOuput $command 
}

#
#Run Command with Command notification
#
for ($i=0; $i -lt 1; $i++) {
    Write-Verbose ''
    Write-Verbose "Command Notification: #$i Sending Command ifconfig InstanceId=$InstanceIds"
    $command = Send-SSMCommand -InstanceIds $InstanceIds -DocumentName 'AWS-RunShellScript' -Parameters @{commands='ifconfig'} `
                  -NotificationConfig_NotificationArn $topic `
                  -NotificationConfig_NotificationType Command `
                  -NotificationConfig_NotificationEvent @('Success', 'TimedOut', 'Cancelled', 'Failed') `
                  -ServiceRoleArn $role.Arn
    Write-Verbose "Sending Command ifconfig CommandId=$($command.CommandId), InstanceId=$InstanceIds"

    receiveMessage -sqs $sqs -expectedCommandId $command.CommandId -expectedDocumententName 'AWS-RunShellScript' -expectedStatus 'Success'
    queueShouldBeEmpty -sqs $sqs
    Test-SSMOuput $command 
}


#
#Notification cleanup
#
Remove-SQSQueue -QueueUrl $sqs -Force
Write-Verbose "Removed SQSQueue $sqs"

Remove-SNSTopic $topic -Force
Write-Verbose "Removed SNSTopic $topic"

return $obj