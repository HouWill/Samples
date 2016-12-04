param (
    $Name = (Get-PSUtilDefaultIfNull -value $Name -defaultValue 'ssmlinux'), 
    $Region = (Get-PSUtilDefaultIfNull -value (Get-DefaultAWSRegion) -defaultValue 'us-east-1'),
    [string] $SetupAction = ''  # SetupOnly or CleanupOnly
    )
#Automation with Lambda
<#
{"ActionDetail": 
  {"Description": "Execute a InvokeLambdaFunction task", 
   "Inputs": 
    [
      {"Name": "FunctionName", 
       "Regex": "(arn:aws:lambda:)?([a-z]{2}-[a-z]+-\\d{1}:)?(\\d{12}:)?(function:)?([a-zA-Z0-9-_]+)(:(\\$LATEST|[a-zA-Z0-9-_]+))?", 
       "Required": true, 
       "Type": "String"}, 
      {"Name": "ClientContext", 
       "Required": false, 
       "Type": "String"}, 
      {"Name": "LogType", 
       "Regex": "\\b(None|Tail)\\b", 
       "Required": false, 
       "Type": "String"}, 
      {"Name": "InvocationType", 
       "Regex": "\\b(RequestResponse|Event|DryRun)\\b", 
       "Required": false, 
       "Type": "String"}, 
      {"Name": "Qualifier", 
       "Regex": "(|[a-zA-Z0-9$_-]+)", 
       "Required": false, 
       "Type": "String"}, 
      {"Name": "Payload", 
       "Required": false, 
       "Type": "String"}
    ], 
   "Name": "aws:invokeLambdaFunction", 
   "Outputs": 
    [
      {"Name": "StatusCode", 
       "Required": true, 
       "Type": "String"}
    ]
  }
}
#>

$DocumentName = "AutomationWithLambda-$Name"
Write-Verbose "DocumentName=$DocumentName, Region=$Region, SetupAction=$SetupAction"

SSMDeleteDocument $DocumentName

if ($SetupAction -eq 'CleanupOnly') {
    return
} 


#step 1. Creates a simple lambda function in python
$code = @'
from __future__ import print_function

import json
import base64

print('Loading function....')

def lambda_handler(event, context):
    print("Received event: " + json.dumps(event, indent=4))

    if 'Records' in event:
        print('RECORDS:')
        for record in event['Records']:
            payload = base64.b64decode(record['kinesis']['data'])
            #payload = json.load(payload)
            print("Payload: " + payload)
    print("logstream = " + context.log_stream_name)
    return context.log_stream_name  # Echo back the first key value
'@

$codeFile = "$($Env:TEMP)\lambda.py"
$zipFile = "$($Env:TEMP)\lambda.zip"
del $zipFile -ea 0
$functionName = 'PSLambda'

$code | Out-File -Encoding ascii $codeFile

Compress-Archive -Path $codeFile -DestinationPath $zipFile

Write-Verbose "Delete Lambda function if present, with Name=$functionName"
Get-LMFunctions | ? FunctionName -eq $functionName | Remove-LMFunction -Force

$null = Publish-LMFunction -FunctionZip $zipFile -FunctionName $functionName -Handler 'lambda.lambda_handler' -Role 'arn:aws:iam::660454403809:role/test' -Runtime python2.7
Write-Verbose "Create Python based Lambda function with Name=$functionName"

$payload = '{"key1": "value1...","key2": "value2"}' | ConvertTo-Json

Invoke-PSUtilIgnoreError {Get-CWLLogStreams -LogGroupName /aws/lambda/PSLambda | Remove-CWLLogStream -LogGroupName /aws/lambda/PSLambda -Force}



$doc = @"
{
  "description": "Lambda Function in Automation Service Demo",
  "schemaVersion": "0.3",
  "assumeRole": "arn:aws:iam::660454403809:role/AMIA",
  "mainSteps": [
    {
      "name": "lambda",
      "action": "aws:invokeLambdaFunction",
      "maxAttempts": 1,
      "onFailure": "Continue",
      "inputs": {
        "FunctionName": "$functionName",
        "Payload": $payload,
        "InvocationType": "RequestResponse",
        "LogType" : "Tail"
      }
    }
  ],
  "outputs":["lambda.StatusCode"]
}
"@

$startTime = Get-Date

#delete if present
if (Get-SSMDocumentList -DocumentFilterList @{key='Name';Value=$DocumentName}) {
    Remove-SSMDocument -Name $DocumentName -Force
}

$ret = New-SSMDocument -Content $doc -DocumentType Automation -Name $DocumentName
Write-Verbose "Document Name=$DocumentName, Content=`n$doc"

$startTime = Get-Date

Write-Verbose "Starting Automation $DocumentName"
$executionid = Start-SSMAutomationExecution -DocumentName $DocumentName 
Write-Verbose "AutomationExecutionId=$executionid"


$cmd = {$execution = Get-SSMAutomationExecution -AutomationExecutionId $executionid; Write-Verbose "AutomationExecutionStatus=$($execution.AutomationExecutionStatus)"; $execution.AutomationExecutionStatus -eq 'Success'}
$null = Invoke-PSUtilWait -Cmd $cmd -Message 'Automation execution' -RetrySeconds 15 -SleepTimeInMilliSeconds 2000

#Stop-SSMAutomationExecution -AutomationExecutionId $execution

$steps = (Get-SSMAutomationExecution -AutomationExecutionId $executionid).StepExecutions

$StatusCode=$steps[0].Outputs['StatusCode'][0]
Write-Verbose "StatusCode=$StatusCode"
if ($StatusCode -ne 200) {
    throw "StatusCode should be 200, instead it is $StatusCode"
}

$obj = @{}
$obj.'AutomationExecutionId' = $executionid
$obj.'Time' = (Get-Date) - $startTime

$obj
if ($SetupAction -eq 'SetupOnly') {
    return $obj
} 

#delete if present
Remove-SSMDocument -Name $DocumentName -Force

