# You should define before running this script.
#    $name - Name identifies logfile and test name in results
#            When running in parallel, name maps to unique ID.
#            Some thing like '0', '1', etc when running in parallel
#     $obj - This is a global dictionary, used to pass output values
#            (e.g.) report the metrics back, or pass output values that will be input to subsequent functions

param ($Name = "ssm", 
    $Region = (Get-PSUtilDefaultIfNull -value (Get-DefaultAWSRegion) -defaultValue 'us-east-1'))

Set-DefaultAWSRegion $Region

$instance = Get-WinEC2Instance $Name -DesiredState 'running'
$instanceId = $instance.InstanceId
Write-Verbose "Name=$Name InstanceId=$instanceId"


#
#Notification setup
#
Register-IAMRolePolicy -RoleName 'test' -PolicyArn 'arn:aws:iam::aws:policy/AmazonSNSFullAccess'

Write-Verbose "Create SNS Topic $name"
$topic = New-SNSTopic -Name $name
Write-Verbose "Topic=$topic"

Write-Verbose "Create SQS Queue $name"
$sqs = New-SQSQueue $name
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
        $message = Receive-SQSMessage -QueueUrl $sqs -WaitTimeInSeconds 1
        if (-not $message) {
            continue
        }
        $json = ConvertFrom-Json (ConvertFrom-Json $message.Body).Message
        Write-Verbose "Received Message: CommandId=$($json.commandId), InstanceId=$($json.InstanceId) DocumententName=$($json.documentName), Status=$($json.status)"

        if ($expectedCommandId -ne $json.commandId) {
            Write-Warning 'Eating unexpected commandId' 
            Remove-SQSMessage -QueueUrl $sqs -ReceiptHandle $message.ReceiptHandle -Force
            continue
        }

        if ($expectedCommandId -ne $json.commandId -or $expectedDocumententName -ne $json.documentName -or $expectedStatus -ne $json.status) {
            throw "Did not match with EXPECTED: CommandId=$expectedCommandId, DocumententName=$expectedDocumententName, Status=$expectedStatus"
        }

        Write-Verbose 'Removing the message'
        Remove-SQSMessage -QueueUrl $sqs -ReceiptHandle $message.ReceiptHandle -Force
        return
    }
    throw "Receive Message Failed: EXPECTED: CommandId=$expectedCommandId, DocumententName=$expectedDocumententName, Status=$expectedStatus"
}



#
#Run Command with invocation notification
#
for ($i=0; $i -lt 5; $i++) {
    Write-Verbose "Sending Command ifconfig InstanceId=$instanceId"
    $command = Send-SSMCommand -InstanceIds $instanceId -DocumentName 'AWS-RunShellScript' -Parameters @{commands='ifconfig'} `
                  -NotificationConfig_NotificationArn $topic `
                  -NotificationConfig_NotificationType Invocation `
                  -NotificationConfig_NotificationEvent @('Success', 'TimedOut', 'Cancelled', 'Failed') `
                  -ServiceRoleArn $role.Arn

    for ($j=0; $j -lt 2*$instance.Count; $j++) {
        receiveMessage -sqs $sqs -expectedCommandId $command.CommandId -expectedDocumententName 'AWS-RunShellScript' -expectedStatus 'Success'
    }
    Test-SSMOuput $command 
}

#
#Run Command with Command notification
#
for ($i=0; $i -lt 5; $i++) {
    Write-Verbose "Sending Command ifconfig InstanceId=$instanceId"
    $command = Send-SSMCommand -InstanceIds $instanceId -DocumentName 'AWS-RunShellScript' -Parameters @{commands='ifconfig'} `
                  -NotificationConfig_NotificationArn $topic `
                  -NotificationConfig_NotificationType Command `
                  -NotificationConfig_NotificationEvent @('Success', 'TimedOut', 'Cancelled', 'Failed') `
                  -ServiceRoleArn $role.Arn

    receiveMessage -sqs $sqs -expectedCommandId $command.CommandId -expectedDocumententName 'AWS-RunShellScript' -expectedStatus 'Success'
    Test-SSMOuput $command 
}

#Publish-SNSMessage -Message '"hello"' -TopicArn $topic
#Clear-SQSQueue -QueueUrl $sqs

#
#Notification cleanup
#
Remove-SQSQueue -QueueUrl $sqs -Force
Remove-SNSTopic $topic -Force

return $obj