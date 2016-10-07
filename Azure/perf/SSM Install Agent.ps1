param ($Name = '', $SSMRegion='us-east-1')

Write-Verbose 'Install SSM Agent'

. "$PSScriptRoot\Common Setup.ps1"

$Name = "perf$Name"

$SecurePassword = ConvertTo-SecureString -String $obj.Password -AsPlainText -Force
$cred = New-Object PSCredential -ArgumentList "siva", $SecurePassword


function SSMInstallAgent ([string]$ConnectionUri, [System.Management.Automation.PSCredential]$Credential, [string]$Region, [string]$DefaultInstanceName)
{
    Write-Verbose "ConnectionUri=$ConnectionUri, DefaultInstanceName=$DefaultInstanceName, Region=$Region"
    $code = New-SSMActivation -DefaultInstanceName $DefaultInstanceName -IamRole 'test' -RegistrationLimit 1 –Region $region
    Write-Verbose "ActivationCode=$($code.ActivationCode), ActivationId=$($code.ActivationId)"

    $sb = {
        param ($Region, $ActivationCode, $ActivationId)

        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force

        $source = "https://amazon-ssm-$region.s3.amazonaws.com/latest/windows_amd64/AmazonSSMAgentSetup.exe"
        $dest = "$($env:TEMP)\AmazonSSMAgentSetup.exe"
        del $dest -ea 0
        $log = "$($env:TEMP)\SSMInstall.log"
        $webclient = New-Object System.Net.WebClient
        $webclient.DownloadFile($source, $dest)

        $a = @('/q', '/log', $log, "CODE=$ActivationCode", "ID=$ActivationId", "REGION=$region", 'ALLOWEC2INSTALL=YES')
        Start-Process $dest -ArgumentList $a -Wait
        #cat $log
        $st = Get-Content ("$($env:ProgramData)\Amazon\SSM\InstanceData\registration")
        Write-Verbose "ProgramData\Amazon\SSM\InstanceData\registration=$st"
        Write-Verbose (Get-Service -Name "AmazonSSMAgent")
    }

    Invoke-Command -ScriptBlock $sb -ConnectionUri $ConnectionUri -Credential $Credential -ArgumentList @($region, $code.ActivationCode, $code.ActivationId) -SessionOption (New-PSSessionOption -SkipCACheck)


    Remove-SSMActivation $code.ActivationId -Force
    $code.ActivationId
}





$obj.'ActivationId' =  SSMInstallAgent -ConnectionUri $obj.ConnectionUri -Credential $cred  -Region $SSMRegion -DefaultInstanceName $Name
