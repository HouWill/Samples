# You should define before running this script.
#    $name - Name identifies logfile and test name in results
#            When running in parallel, name maps to unique ID.
#            Some thing like '0', '1', etc when running in parallel


param ($Name = 'ssm-windows',
        $MSIPath1 = 'https://downloads.sourceforge.net/project/sevenzip/7-Zip/15.12/7z1512-x64.msi',
        $MSIPath2 = 'https://downloads.sourceforge.net/project/sevenzip/7-Zip/16.04/7z1604-x64.msi',
        $Region = (Get-PSUtilDefaultIfNull -value (Get-DefaultAWSRegion) -defaultValue 'us-east-1'))

Write-Verbose "Windows Run Command Name=$Name, MSIPath=$MSIPath, Region=$Region"
Set-DefaultAWSRegion $Region

$instance = Get-WinEC2Instance $Name -DesiredState 'running'
$instanceId = $instance.InstanceId
Write-Verbose "Name=$Name InstanceId=$instanceId"


#Run Command
Write-Verbose 'Run Command - AWS-InstallApplication'
$startTime = Get-Date
$command = SSMRunCommand `
    -InstanceIds $instanceId `
    -DocumentName 'AWS-InstallApplication' `
    -Parameters @{
        source=$MSIPath1
        action='Install'
     } 

$obj = @{}
$obj.'CommandId' = $command
$obj.'RunCommandTime' = (Get-Date) - $startTime


$command = SSMRunCommand `
    -InstanceIds $instanceId `
    -Parameters @{
        commands='gwmi win32_product | ? Name -like "7-zip*" | select Name'
     } 
Test-SSMOuput $command -ExpectedMinLength 187 -ExpectedMaxLength 187



#Upgrade
$startTime = Get-Date
$command = SSMRunCommand `
    -InstanceIds $instanceId `
    -DocumentName 'AWS-InstallApplication' `
    -Parameters @{
        source=$MSIPath2
     } 
$command = SSMRunCommand `
    -InstanceIds $instanceId `
    -Parameters @{
        commands='gwmi win32_product | ? Name -like "7-zip*" | select Name'
     } 
Test-SSMOuput $command -ExpectedMinLength 187 -ExpectedMaxLength 187




#Uninstall

$startTime = Get-Date
$command = SSMRunCommand `
    -InstanceIds $instanceId `
    -DocumentName 'AWS-InstallApplication' `
    -Parameters @{
        source=$MSIPath2
        action='Uninstall'
     } 
$command = SSMRunCommand `
    -InstanceIds $instanceId `
    -Parameters @{
        commands='gwmi win32_product | ? Name -like "7-zip*" | select Name'
     } 
Test-SSMOuput $command -ExpectedMinLength 0 -ExpectedMaxLength 0





return $obj