param (
    $Name = (Get-PSUtilDefaultIfNull -value $Name -defaultValue 'ssmlinux'), 
    $InstanceIds = $InstanceIds,
    $Region = (Get-PSUtilDefaultIfNull -value (Get-DefaultAWSRegion) -defaultValue 'us-east-1'),
    [string] $SetupAction = ''  # SetupOnly or CleanupOnly
    )

Set-DefaultAWSRegion $Region

if ($InstanceIds.Count -eq 0) {
    Write-Verbose "InstanceIds is empty, retreiving instance with Name=$Name"
    $InstanceIds = (Get-WinEC2Instance $Name -DesiredState 'running').InstanceId
}
$DocumentName = "ParameterStore-$Name"

Write-Verbose "Linux RC4 Param: InstanceIds=$InstanceIds, DocumentName=$DocumentName"

$doc = @'
{
    "schemaVersion": "2.0",
    "description": "Example instance configuration tasks for 2.0",
    "parameters":{
        "hello":{
            "type":"String",
            "description":"(Optional) List of association ids. If empty, all associations bound to the specified target are applied.",
            "displayType":"textarea",
            "default": "{{ssm:hello}}"
        }
    },
    "mainSteps": [
        {
            "action": "aws:runShellScript",
            "name": "run",
            "inputs": {
                "runCommand": [
                    "echo Doc1.v1 - {{ hello }}"
                 ]
            }
        }
    ]
}
'@

function Cleanup () {
    SSMDeleteDocument $DocumentName
    if (Get-SSMParameterList -Filter @{Key='Name';Values='hello'}) {
        Remove-SSMParameter -Name 'hello' -Force
    }
}
Cleanup
if ($SetupAction -eq 'CleanupOnly') {
    return
} 

SSMCreateDocument $DocumentName $doc
Write-SSMParameter -Name 'hello' -Value 'world' -Type String

$startTime = Get-Date
$command = SSMRunCommand -InstanceIds $InstanceIds -SleepTimeInMilliSeconds 1000 `
    -DocumentName $DocumentName -Parameters @{hello='{{ssm:hello}}'}

Test-SSMOuput $command -ExpectedOutput 'world' -ExpectedMinLength 10 

Write-Verbose "Time = $((Get-Date) - $startTime)"

if ($SetupAction -eq 'SetupOnly') {
    return
}

Cleanup