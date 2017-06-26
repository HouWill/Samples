param (
    $PsTestObject,
    $Region = (Get-PSUtilDefaultIfNull -value (Get-DefaultAWSRegion) -defaultValue 'us-east-1')
)

. $PSScriptRoot\ssmcommon.ps1
Set-DefaultAWSRegion $Region

$sb = New-Object System.Text.StringBuilder
$sb.AppendLine("Relevent Information:")

function SSMGetInstanceInformation ($InstanceIds, $sb = $null) {
    $instances = Get-WinEC2Instance -NameOrInstanceIds ($InstanceIds -join ',')

    if (! $sb) {
        $sb = New-Object System.Text.StringBuilder
    }
    foreach ($instance in $Instances) {
        $null = $sb.AppendLine("InstanceId=$($instance.InstanceId), Platform=$($instance.PlatformName), State=$($instance.State), SSMStatus=$($instance.SSMPingStatus), AgentVersion=$($instance.AgentVersion)")
    }
    return $sb
}

if ($PsTestObject.InstanceIds) {
    $sb = SSMGetInstanceInformation $PsTestObject.InstanceIds -sb $sb
    $null = $sb.AppendLine()
}

if ($PsTestObject.CommandId) {
    $sb = SSMGetCommandInformation $PsTestObject.CommandId -sb $sb
    $null = $sb.AppendLine()
}
if ($PsTestObject.AssociationId) {
    $sb = SSMGetAssociationInformation $PsTestObject.AssociationId -sb $sb
    $null = $sb.AppendLine()
}
if ($PsTestObject.AutomationExecutionId) {
    $sb = SSMGetAutomationExecutionInformation $PsTestObject.AutomationExecutionId -sb $sb
    $null = $sb.AppendLine()
}


Write-Verbose $sb.ToString()
