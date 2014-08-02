trap { break }
$ErrorActionPreference = 'Stop'

$Count = 1
$RetryCount = 10
$fileprefix = 'c:\temp\x'
$processTrottle = 4

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


Update-WinEC2FireWallSource
Remove-WinEC2Instance *

$parameterSets = Explode $parameterSets 'InstanceTypes' @('t2.medium', 'm3.xlarge')
$parameterSets = Explode $parameterSets 'gp2' @($true, $false)
$parameterSets = Explode $parameterSets 'ImagePrefix' @('Windows_Server-2012-R2_RTM-English-64Bit-Base')

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
        }
        elseif ($proceslist[$j] -ne 0) 
        {
            $continue = $true
            try
            {
                Wait-process -id $proceslist[$j].Id -Timeout 1
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
        "" >> $consolidatedfile
        $csvfile >> $consolidatedfile
        cat $csvfile >> $consolidatedfile
    }
}
