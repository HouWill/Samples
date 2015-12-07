#Set-DefaultAWSRegion 'us-east-1'
Set-DefaultAWSRegion 'us-west-2'
$VerbosePreference='Continue'
trap { break } #This stops execution on any exception
$ErrorActionPreference = 'Stop'

cd $PSScriptRoot
. .\ssmcommon.ps1

$index = '1'
if ($psISE -ne $null)
{
    #Role name is suffixed with the index corresponding to the ISE tab
    #Ensures to run multiple scripts concurrently without conflict.
    $index = $psISE.CurrentPowerShellTab.DisplayName.Split(' ')[1]
}
$instanceName = "ssm-demo-$index"

SSMCreateRole
SSMCreateKeypair
SSMCreateSecurityGroup 

$instanceId = SSMCreateInstance -Tag $instanceName




$command = SSMRunCommand `
    -InstanceIds $instanceId `
    -Parameters @{
        commands=@(
        '$url = "https://chocolatey.org/install.ps1"',
        'iex ((new-object net.webclient).DownloadString($url)) *> $null',
        'choco install googlechrome wget --confirm',
        "choco list --localonly"
        )
     }  `
    -Outputs3BucketName 'sivapdxbucket'
SSMDumpOutput $command

Read-Host 'after chaco install'

$command = SSMRunCommand `
    -InstanceIds $instanceId `
    -Parameters @{
        commands=@(
        '$url = "https://chocolatey.org/install.ps1"',
        'iex ((new-object net.webclient).DownloadString($url)) *>$null',
        'choco uninstall googlechrome wget --confirm',
        "choco list --localonly"
        )
     }  `
    -Outputs3BucketName 'sivapdxbucket'
SSMDumpOutput $command

Read-Host 'after chaco uninstall'


$command = SSMRunCommand `
    -InstanceIds $instanceId `
    -DocumentName 'AWS-InstallApplication' `
    -Parameters @{
        source='http://downloads.sourceforge.net/project/sevenzip/7-Zip/15.12/7z1512-x64.msi'
     } 
SSMDumpOutput $command

$command = SSMRunCommand `
    -InstanceIds $instanceId `
    -Parameters @{
        commands='gwmi win32_product | select Name'
     }  `
    -Outputs3BucketName 'sivapdxbucket'
SSMDumpOutput $command
Read-Host 'after 7zip install'

$command = SSMRunCommand `
    -InstanceIds $instanceId `
    -DocumentName 'AWS-InstallApplication' `
    -Parameters @{
        source='http://downloads.sourceforge.net/project/sevenzip/7-Zip/15.12/7z1512-x64.msi'
        action='Uninstall'
     } 
SSMDumpOutput $command

$command = SSMRunCommand `
    -InstanceIds $instanceId `
    -Parameters @{
        commands='gwmi win32_product | select Name'
     }  `
    -Outputs3BucketName 'sivapdxbucket'
SSMDumpOutput $command
Read-Host 'after 7zip uninstall'


function PSUtilZipFolder(
    $SourceFolder, 
    $ZipFileName, 
    $IncludeBaseDirectory = $true)
{
    del $ZipFileName -ErrorAction 0
    Add-Type -Assembly System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($SourceFolder,
        $ZipFileName, [System.IO.Compression.CompressionLevel]::Optimal, 
        $IncludeBaseDirectory)
}

$dir = pwd
PSUtilZipFolder -SourceFolder "$dir\PSDemo" `
    -ZipFileName "$dir\PSDemo.zip" -IncludeBaseDirectory $false
write-S3Object -BucketName 'sivapdxbucket' -key 'public/PSDemo.zip' `
    -File $dir\PSDemo.zip -PublicReadOnly
del $dir\PSDemo.zip 

$command = SSMRunCommand `
    -InstanceIds $instanceId `
    -DocumentName 'AWS-InstallPowerShellModule' `
    -Parameters @{
        source='https://s3.amazonaws.com/sivapdxbucket/public/PSDemo.zip'
        commands=@('Test1')
     }  `
    -Outputs3BucketName 'sivapdxbucket'
SSMDumpOutput $command

Remove-S3Object -BucketName 'sivapdxbucket' -Key 'public/PSDemo.zip' -Force

Read-Host "After PSDemo module"

#Cleanup
SSMRemoveInstance $instanceName

#SSMRemoveRole

#SSMRemoveKeypair

#SSMRemoveSecurityGroup 
