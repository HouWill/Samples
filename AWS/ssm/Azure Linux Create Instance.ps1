# You should define before running this script.
#    $name - Name identifies logfile and test name in results
#            When running in parallel, name maps to unique ID.
#            Some thing like '0', '1', etc when running in parallel
#     $obj - This is a dictionary, used to pass output values
#            (e.g.) report the metrics back, or pass output values that will be input to subsequent functions

param ( $Name = '',
        $Region = 'West US',
        $InstanceType = 'Standard_D1_v2', # 'Medium', #'Small',
        $ImagePrefix='Ubuntu Server 14',
        $Key = 'c:\keys\test',
        $linuxUser='siva',
        $SSMRegion='us-east-1'
)

. "$PSScriptRoot\Common Setup.ps1"

$image = Get-AzureVMImage | ? label -Like "$ImagePrefix*"  | sort PublishedDate -Descending | select -First 1
Write-Verbose "Image = $($image.Label)"
if ($image -eq $null) {
    throw "Image with prefix $ImagePrefix not found"
}

$location = Get-AzureLocation | ? Name -EQ $Region
Write-Verbose "Location/Region = $($location.Name)"

$name = "mc-$(Get-Random)"
Write-Verbose "Service and Instance Name=$name"

#Given it is a test instance, and deleted right, the password is printed. Bad idea for real use case!
$password = "pass-$(Get-Random)"
Write-Verbose "Generated Password=$password"
$obj.'Password' = $password

$Obj.'Name' = $name
$Obj.'InstanceType' = $InstanceType
$Obj.'Image' = $image.Label

$startTime = Get-Date

#openssl.exe req -x509 -nodes -days 365 -newkey rsa:2048 -keyout myPrivateKey.key -out myCert.pem -subj "/C=US/ST=WA/L=none/O=none/CN=www.example.com"

#Start-Process openssl -ArgumentList @('req','-x509','-nodes', '-days', '365', '-newkey', 'rsa:2048', '-keyout', 'myPrivateKey.key', '-out', 'myCert.pem',
#                                    '-subj', '/C=US/ST=WA/L=none/O=none/CN=www.example.com', '-pubkey') -Wait 

$vmName = "linux1"

New-KeyPairs $key

$azureService = New-AzureService -ServiceName $Name -Location $Region 

$cert = Get-PfxCertificate -FilePath "$key.cert"
$azureCertificate = Add-AzureCertificate -CertToDeploy "$key.cert" -ServiceName $Name

$sshKey = New-AzureSSHKey -PublicKey -Fingerprint $cert.Thumbprint -Path "/home/$linuxUser/.ssh/authorized_keys"

$null = New-AzureVMConfig -Name $vmName -InstanceSize $InstanceType -ImageName $image.ImageName  |
    Add-AzureProvisioningConfig -Linux -LinuxUser $linuxUser -NoSSHPassword -SSHPublicKeys $sshKey  |
    New-AzureVM -ServiceName $Name -WaitForBoot 

$VM = Get-AzureVM -ServiceName $name -Name $vmName
$endpoint = Get-AzureEndpoint -VM $VM

<#
$blob = Get-AzureStorageContainer | Get-AzureStorageBlob | ? name -like "$name*-seriallog.txt"
$cmd = {
        $null = $blob | Get-AzureStorageBlobContent -Force
        $script:log = cat $blob.Name 
        $log | where { $_ -like 'ecdsa-sha2-nistp256*' }}
$null = Invoke-PSUtilWait -Cmd $cmd -Message 'ecdsa-sha2-nistp256 in log' -PrintAllErrors
#>


Invoke-SSHCommand -key "$key.pem" -user $linuxUser -remote $endpoint.Vip -port $endpoint.Port -cmd "ps"

$Obj.'BootTime' = $runningTime - $startTime
$Obj.'RemoteTime' = $remoteTime - $startTime

$obj.'InstanceId' =  SSMLinuxInstallAgent -key "$key.pem" -user $linuxUser -remote $endpoint.Vip -port $endpoint.Port -IAMRole 'test' -Region $SSMRegion -DefaultInstanceName $vmName
