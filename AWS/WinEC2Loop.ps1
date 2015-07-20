trap { break }
$ErrorActionPreference = 'Stop'

$Count = 10
$RetryCount = 10
$fileprefix = 'c:\temp\x'
$processTrottle = 4

Write-Verbose "Count=$Count, RetryCount=$RetryCount, fileprefix=$fileprefix, processTrottle=$processTrottle"

[Hashtable[]]$parameterSets = @(
    @{
    }
)

function Explode ([Hashtable[]]$parameterSets, 
                  [string]$key,
                  [object[]]$values)
{
    [Hashtable[]] $results = @()

    foreach ($parameterSet in $parameterSets)
    {
        foreach ($value in $values)
        {
            [Hashtable]$tempParameterSet = $parameterSet.Clone()
            $tempParameterSet.Add($key, $value)
            $results += $tempParameterSet
        }
    }
    $results
}


$parameterSets = Explode $parameterSets 'InstanceType' @('t2.micro')
<#
$parameterSets = Explode $parameterSets 'InstanceType' @('t2.micro', 't2.small', 't2.medium', 
                'm3.medium', 'm3.large', 'm3.xlarge', 'm3.2xlarge',
                'c3.large', 'c3.xlarge', 'c3.2xlarge', 'c3.4xlarge', 'c3.8xlarge', 
                'r3.large', 'r3.xlarge', 'r3.2xlarge', 'r3.4xlarge', 'r3.8xlarge', 
                'i2.xlarge', 'i2.2xlarge', 'i2.4xlarge', 'i2.8xlarge', 
                'hs1.8xlarge', 'g2.2xlarge')
#>
$parameterSets = Explode $parameterSets 'ImagePrefix' @('Windows_Server-2012-R2_RTM-English-64Bit-Base')
$parameterSets = Explode $parameterSets 'Region' @('us-east-1')
$parameterSets = Explode $parameterSets 'IOPS' @(0)
$parameterSets = Explode $parameterSets 'gp2' @($true)

$i = 0
$ps1files = New-Object System.Collections.ArrayList

foreach ($parameterSet in $parameterSets)
{
    $i++
    $csvfile = "$($fileprefix)$($i).csv"
    $ps1file = "$($fileprefix)$($i).ps1"
    $null = $ps1files.Add($ps1file)

    @"
(get-host).ui.RawUI.WindowTitle = `$MyInvocation.MyCommand.Name
. '$PSScriptRoot\WinEC2.ps1'
. '$PSScriptRoot\WinEC2LoopRunOne.ps1'
"@ > $ps1file
    '$parameters = @{'>> $ps1file
    foreach ($key in $parameterSet.Keys)
    {
        $value = $parameterSet[$key]
        if ($value -is [Boolean])
        {
            "    $key=`$$value">> $ps1file
        }
        else
        {
            "    $key='$value'">> $ps1file
        }
    }
    "}" >> $ps1file

    "WinEC2LoopRunOne -file `"$csvfile`" -count $Count -retryCount $RetryCount -parameterSet `$parameters" >> $ps1file
}

Write-Verbose "Generated $i files ($fileprefix*)"

$proceslist = ,0*$processTrottle

$continue = $true
while ($continue)
{
    $continue = $false

    for ($j = 0; $j -lt $processTrottle; $j++)
    {
        if ($proceslist[$j] -eq 0 -and $ps1files.Count -gt 0)
        {
            $continue = $true
            $ps1file = $ps1files[0]
            $ps1files.RemoveAt(0)
            $proceslist[$j] = Start-Process "$PSHOME\PowerShell.exe" -ArgumentList "-f `"$ps1file`"" -PassThru
            Write-Verbose "Started $ps1file ProcessId=$($proceslist[$j].id), Remaining=$($ps1files.Count)"
        }
        elseif ($proceslist[$j] -ne 0) 
        {
            $continue = $true
            try
            {
                Wait-process -id $proceslist[$j].Id -Timeout 1
                Write-Verbose "Completed ProcessId=$($proceslist[$j].id)"
                $proceslist[$j] = 0
            }
            catch
            {
                if (-not (Get-Process -id $proceslist[$j].Id -ea 0))
                {
                    $proceslist[$j] = 0
                }
            }
        }
    }
}

$consolidatedfile = "$fileprefix.csv"
del $consolidatedfile -ea 0 
for ($j = 1; $j -le $i; $j++)
{
    $csvfile = "$($fileprefix)$($j).csv"
    if (Test-Path $csvfile)
    {
        $csvfile >> $consolidatedfile
        cat $csvfile >> $consolidatedfile
    }
}
