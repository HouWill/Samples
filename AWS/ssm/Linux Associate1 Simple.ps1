param (
    $Name = (Get-PSUtilDefaultIfNull -value $Name -defaultValue 'ssmlinux'), 
    $InstanceIds = $InstanceIds,
    $Region = (Get-PSUtilDefaultIfNull -value (Get-DefaultAWSRegion) -defaultValue 'us-east-1')
    )

Set-DefaultAWSRegion $Region

if ($InstanceIds.Count -eq 0) {
    Write-Verbose "InstanceIds is empty, retreiving instance with Name=$Name"
    $instances = Get-WinEC2Instance $Name -DesiredState 'running'
    $InstanceIds = $instances.InstanceId
} else {
    $instances = Get-WinEC2Instance ($InstanceIds -join ',')
}

$DocumentName = 'AssociateRunShellScript'
Write-Verbose "Linux Associate 1: InstanceIds=$($instances.InstanceId)"

function getdocument ($Message) {
    $doc = @"
{
    "schemaVersion": "2.0",
    "description": "Example instance configuration tasks for 2.0",
    "parameters":{
        "hello":{
            "type":"String",
            "description":"(Optional) List of association ids. If empty, all associations bound to the specified target are applied.",
            "displayType":"textarea",
            "default": "default"
        }
    },
    "mainSteps": [
        {
            "action": "aws:runShellScript",
            "name": "run",
            "inputs": {
                "runCommand": ["echo Doc1.v$Message - {{ hello }}"]
            }
        }
    ]
}
"@

    return $doc
}

SSMDeleteDocument $DocumentName

#Restart Agent and wait for mapping to be cleared
#SSMReStartAgent $instances

SSMWaitForAssociation -InstanceId $instances.InstanceId -ExpectedAssociationCount 0 -MinS3OutputSize 0

#Create Document
SSMCreateDocument $DocumentName (getdocument '1')

$startTime = Get-Date

$associationIds = @()
$output = SSMAssociateTarget $DocumentName @{Key='instanceids';Values=$instances.InstanceId} @{hello=@('one')}
$associationIds += $output.AssociationId
    
$tagAssociationid = (SSMAssociateTarget $DocumentName @{Key='tag:Name';Values=$Name} @{hello=@('one')}).Associationid
$associationIds += $tagAssociationid

SSMWaitForMapping -InstanceIds $instances.InstanceId -AssociationCount 2

SSMRefreshAssociation $instances.InstanceId  #($associationIds -join ',')

SSMWaitForAssociation -InstanceId $instances.InstanceId -ExpectedAssociationCount 2 -MinS3OutputSize 13 -ContainsString 'Doc1.v1 - one' 

$convergenceTime = Get-Date
Remove-SSMAssociation -AssociationId $tagAssociationid -Force

$doc1v2 = getdocument '2'
$null = Update-SSMDocument -Content $doc1v2 -Name $DocumentName -DocumentVersion '$LATEST'
$null = Update-SSMDocumentDefaultVersion -Name $DocumentName -DocumentVersion '2'
$a = Get-SSMDocument -Name $DocumentName
if ($a.Content -ne $doc1v2) {
    throw "Document content did not match after update. Expected:`n$doc1v2`nRetrieved:`n$($a.Content)"
}
Write-Verbose "$($DocumentName.1) updated to v2"

SSMWaitForMapping -InstanceIds $instances.InstanceId -AssociationCount 1
    
SSMRefreshAssociation $instances.InstanceId ''

SSMWaitForAssociation -InstanceIds $instances.InstanceId -ExpectedAssociationCount 1 -MinS3OutputSize 13 -ContainsString 'Doc1.v2 - one' 

if ($true) {
    $cmd = {
        #$associations = (aws ssm list-associations --endpoint-url $endpoint | ConvertFrom-Json).Associations
        $associations = Get-SSMAssociationList 
        $found = $true
        foreach ($association in $associations) {
            [int]$success = $association.Overview.AssociationStatusAggregatedCount.'Success'
            [int]$pending = $association.Overview.AssociationStatusAggregatedCount.'Pending'
            Write-Verbose "AssociationId=$($association.AssociationId), Pending=$pending, Success=$success"
            if ($pending -gt 0) {
                $found = $false
            }
        }
        return $found
    }
    $null = Invoke-PSUtilWait -Cmd $cmd -Message 'Aggregate convergence' -RetrySeconds 1000 -PrintVerbose
    $aggregationTime = Get-Date
    Write-Verbose "Aggregation Time = $($aggregationTime - $startTime)"
}
$aggregationTime = Get-Date

Write-Verbose "Convergence Time = $($convergenceTime - $startTime)"
Write-Verbose "Aggregation Time = $($aggregationTime - $convergenceTime)"

SSMDeleteDocument $DocumentName
