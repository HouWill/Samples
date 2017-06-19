param (
    $Name = (Get-PSUtilDefaultIfNull -value $Name -defaultValue 'ssmlinux'), 
    $InstanceIds = $InstanceIds,
    $Region = (Get-PSUtilDefaultIfNull -value (Get-DefaultAWSRegion) -defaultValue 'us-east-1')
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

#Get-SSMAssociationList | % { Remove-SSMAssociation -AssociationId $_.AssociationId -Force }

Write-Verbose "Linux Associate 1: InstanceIds=$($instances.InstanceId)"

if ((Get-Random) % 2 -eq 0) {
    Write-Verbose 'Associate with Tag'
    $query = @{Key='tag:Name';Values=$Name}
} else {
    Write-Verbose 'Associate with InstanceID'
    $query = @{Key='instanceids';Values=$instances.InstanceId}
}

$associationId = (SSMAssociateTarget 'AWS-RunShellScript' $query @{commands=@('ifconfig')}).Associationid
Write-Verbose "#PSTEST# AssociationId=$associationId"

SSMWaitForMapping -InstanceIds $instances.InstanceId -AssociationCount 1 -AssociationId $associationId
SSMRefreshAssociation $instances.InstanceId
SSMWaitForAssociation -InstanceId $instances.InstanceId -ExpectedAssociationCount 1 -MinS3OutputSize 13 -AssociationId $associationId

Remove-SSMAssociation -AssociationId $associationId -Force

@{
    AssociationID = $associationId
}