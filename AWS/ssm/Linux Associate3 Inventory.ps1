param (
    $Name = (Get-PSUtilDefaultIfNull -value $Name -defaultValue 'ssmlinux'), 
    $InstanceIds = $InstanceIds,
    $Region = (Get-PSUtilDefaultIfNull -value (Get-DefaultAWSRegion) -defaultValue 'us-east-1'),
    [string] $SetupAction = ''  # SetupOnly or CleanupOnly
    )

. $PSScriptRoot\ssmcommon.ps1
Set-DefaultAWSRegion $Region

if ($InstanceIds.Count -eq 0) {
    Write-Verbose "InstanceIds is empty, retreiving instance with Name=$Name"
    $instances = Get-WinEC2Instance $Name -DesiredState 'running'
    $InstanceIds = $instances.InstanceId
} else {
    $instances = Get-WinEC2Instance ($InstanceIds -join ',')
}

$DocumentName = 'AWS-GatherSoftwareInventory'
Write-Verbose "Linux Associate3 Inventory: InstanceIds=$($instances.InstanceId), DocumentName=$DocumentName"
SSMDeleteAssociation $DocumentName

function appState ($app, $action, $associationId) {
    Invoke-WinEC2Command $instances "sudo yum $action $app -y" | Write-Verbose    

    SSMRefreshAssociation $instances.InstanceId

    SSMWaitForAssociation -InstanceId $instances.InstanceId -ExpectedAssociationCount 1 -MinS3OutputSize 0 -AssociationId $associationId

    if ($action -eq 'install') {
        $count = 1
    } else {
        $count = 0
    }
    foreach ($instance in $instances) {
        $cmd = {
            $entries = (Get-SSMInventoryEntriesList -InstanceId $instance.InstanceId -TypeName 'AWS:Application' -Filter @{Key='AWS:Application.Name';Values='bc';Type='Equal'}).Entries
            Write-Verbose "Inventory Enteries for app=$app, action=$action, Expected=$count, received count=$($entries.Count)"
            $entries.Count -eq $count
        }
        
        $null = Invoke-PSUtilWait -Cmd $cmd -Message "bc $action" -RetrySeconds 60 -SleepTimeInMilliSeconds 1000    
    }
}

if ($SetupAction -eq 'CleanupOnly') {
    return
} 

#Create Association
$associationId = (SSMAssociateTarget $DocumentName @{Key='instanceids';Values=$instances.InstanceId}).AssociationId
Write-Verbose "#PSTEST# AssociationId=$associationId"
SSMWaitForMapping -InstanceIds $instances.InstanceId -AssociationCount 1 -AssociationId $associationId

#return hashtable
@{AssociationId=$associationId} 
if ($SetupAction -eq 'SetupOnly') {
    return
} 

#Install App
appState 'bc' 'install' $associationId


#Remove App
appState 'bc' 'remove' $associationId