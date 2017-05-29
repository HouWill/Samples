param (
    $Name = (Get-PSUtilDefaultIfNull -value $Name -defaultValue 'ssmlinux'), 
    $InstanceIds = $InstanceIds,
    $Region = (Get-PSUtilDefaultIfNull -value (Get-DefaultAWSRegion) -defaultValue 'us-east-1'),
    [string] $SetupAction = ''  # SetupOnly or CleanupOnly
    )

Set-DefaultAWSRegion $Region

if ($InstanceIds.Count -eq 0) {
    Write-Verbose "InstanceIds is empty, retreiving instance with Name=$Name"
    $instances = Get-WinEC2Instance $Name -DesiredState 'running'
    $InstanceIds = $instances.InstanceId
} else {
    $instances = Get-WinEC2Instance ($InstanceIds -join ',')
}

$DocumentName = "Inventory-$Name"
Write-Verbose "Linux Associate 2 Inventory: InstanceIds=$($instances.InstanceId), DocumentName=$DocumentName"


$inventoryDocument = @'
{
    "schemaVersion": "2.0",
    "description": "Software Inventory Policy Document",
    "parameters": {
        "Applications": {
            "type": "String",
            "default": "Enabled",
            "description": "(Optional) Collect data for applications",
            "allowedValues": [
                "Enabled",
                "Disabled"
            ]
        },
        "AWSComponents": {
            "type": "String",
            "default": "Enabled",
            "description": "(Optional) Collect data for AWS Components like amazon-ssm-agent",
            "allowedValues": [
                "Enabled",
                "Disabled"
            ]
        },
        "NetworkConfig": {
            "type": "String",
            "default": "Enabled",
            "description": "(Optional) Collect data for Network configuration",
            "allowedValues": [
                "Enabled",
                "Disabled"
            ]
        },
        "WindowsUpdates": {
            "type": "String",
            "default": "Enabled",
            "description": "(Optional) Collect data for all Windows Updates.",
            "allowedValues": [
                "Enabled",
                "Disabled"
            ]
        },
       "CustomInventory": {
            "type": "String",
            "default": "Enabled",
            "description": "(Optional) Collect data for Custom Inventory",
            "allowedValues": [
                "Enabled",
                "Disabled"
            ]
        },
        "CustomInventoryDirectory": {
            "type": "String",
            "default": "",
            "description": "(Optional) The directory of custom inventory",
            "maxChars": 4096
        }
    },
    "mainSteps": [
        {
            "action": "aws:softwareInventory",
            "name": "CollectSoftwareInventoryItems",
            "inputs": {
                "Applications": "{{ Applications }}",
                "AWSComponents": "{{ AWSComponents }}",
                "NetworkConfig": "{{ NetworkConfig }}",
                "WindowsUpdates": "{{ WindowsUpdates }}",
                "CustomInventory": "{{ CustomInventory }}",
                "CustomInventoryDirectory": "{{ CustomInventoryDirectory }}"
            }
        }
    ]
}
'@



function appState ($app, $action) {
    Invoke-WinEC2Command $instances "sudo yum $action $app -y" | Write-Verbose    

    SSMRefreshAssociation $instances.InstanceId

    SSMWaitForAssociation -InstanceId $instances.InstanceId -ExpectedAssociationCount 1 -MinS3OutputSize 0

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
        
        $null = Invoke-PSUtilWait -Cmd $cmd -Message "bc $action" -RetrySeconds 30 -SleepTimeInMilliSeconds 1000    
    }
}

SSMDeleteDocument $DocumentName

if ($SetupAction -eq 'CleanupOnly') {
    return
} 

SSMCreateDocument $DocumentName $inventoryDocument -DocumentType 'Policy'

#Restart Agent and wait for mapping to be cleared
#SSMReStartAgent $instances

SSMWaitForAssociation -InstanceId $instances.InstanceId -ExpectedAssociationCount 0 -MinS3OutputSize 0

$startTime = Get-Date

#Create Association
$association = SSMAssociateTarget $DocumentName @{Key='instanceids';Values=$instances.InstanceId}
Write-Verbose "New AssociationId=$($association.AssociationId)"
SSMWaitForMapping -InstanceIds $instances.InstanceId -AssociationCount 1

if ($SetupAction -eq 'SetupOnly') {
    return $obj
} 

#Install App
appState 'bc' 'install'


#Remove App
appState 'bc' 'remove'

Write-Verbose "Time = $((Get-Date) - $startTime)"

SSMDeleteDocument $DocumentName
