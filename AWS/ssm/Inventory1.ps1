param (
    $Name = (Get-PSUtilDefaultIfNull -value $Name -defaultValue 'ssmlinux'), 
    $InstanceIds = $InstanceIds,
    $Region = (Get-PSUtilDefaultIfNull -value (Get-DefaultAWSRegion) -defaultValue 'us-east-1')
    )

Set-DefaultAWSRegion $Region

if ($InstanceIds.Count -eq 0) {
    Write-Verbose "InstanceIds is empty, retreiving instance with Name=$Name"
    $InstanceIds = (Get-WinEC2Instance $Name -DesiredState 'running').InstanceId
}
Write-Verbose "Inventory 1: InstanceIds=$InstanceIds"


function GetApplicationItem ($Name, $Publisher, $URL, $Version, $ApplicationType, $InstalledTime, $Architecture) {
    $item = New-Object 'System.Collections.Generic.Dictionary[String,String]'
    $item.Add('Name',$Name)
    $item.Add('Publisher',$Publisher)
    $item.Add('URL',$URL)
    $item.Add('Version',$Version)
    $item.Add('ApplicationType',$ApplicationType)
    $item.Add('InstalledTime',$InstalledTime)
    $item.Add('Architecture',$Architecture)
    $item
}


foreach ($instanceId in $InstanceIds) {
    Write-Verbose "InstanceId=$instanceId"

    $item = New-Object "Amazon.SimpleSystemsManagement.Model.InventoryItem"
    $item.CaptureTime = '2016-08-22T10:01:01Z'
    $item.SchemaVersion='1.0'
    $item.TypeName='AWS:Application'
    $item.Content.Add((GetApplicationItem "acl$Name" 'Amazon.com'  'http://acl.bestbits.at/' '2.2.49' 'System Environment/Base' '2016-09-23T10:01:17Z'  'x86_64'))
    $item.Content.Add((GetApplicationItem "acpid$Name" 'Amazon.com'  'http://acpid.sourceforge.net/' '1.0.10' 'System Environment/Daemons' '2016-09-23T10:01:13Z'  'x86_64'))

    Write-SSMInventory -InstanceId $instanceId -Item $item

    $found = $false
    for ($retryCount=0; $retryCount -lt 10; $retryCount++) {
        if ($retryCount -gt 0) {
            Write-Verbose "Sleeping 2 seconds, as Inventory data did not match}"
            sleep 2
        }

        $output = Get-SSMInventoryEntriesList -InstanceId $instanceId -TypeName 'AWS:Application'
        if ($output.Entries[0].Name -eq "acl$Name" -and $output.Entries[1].Name -eq "acpid$Name") {
            Write-Verbose "Inventory matched!"
            $found = $true
            break
        }
    }
    if (-not $found) {
        throw "Data mismatch. InstanceId=$instanceId, Expected=acl$Name or acpid$Name, received=$($output.Entries.Name)"
    }

    $found = $false
    for ($retryCount=0; $retryCount -lt 25; $retryCount++) {
        if ($retryCount -gt 0) {
            Write-Verbose "Sleeping $($retryCount*5)/$($retryCount*100) seconds, as AWS Config data did not match}"
            sleep 5
        }

        $output = Get-CFGResourceConfigHistory -ResourceType 'AWS::SSM::ManagedInstanceInventory' -ChronologicalOrder Reverse `
                        -ResourceId $instanceId -Limit 1 #-EndpointUrl 'https://falcon.gamma.us-east-1.amazonaws.com' 


        $apps = ($output.configuration | convertfrom-json).'AWS:Application'.Content

        if ($apps."acl$Name" -and $apps."acpid$Name" -and $apps."acl$Name".Name -eq "acl$Name" -and $apps."acpid$Name".Name -eq "acpid$Name") {
            Write-Verbose "AWS Config matched, RetryCount=$retryCount!"
            $found = $true
            break
        }
    }

    if (-not $found) {
        throw "Data mismatch. InstanceId=$instanceId, for 'AWS:Application'"
    }

    Write-Verbose ''
}
