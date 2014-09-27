$count = 50
$file = "$PSScriptRoot\driver.ps1"
$file

Import-Module $PSScriptRoot\test.psm1 -Force
cls

$proceslist = ,0*$count
$prevstat = $null
$prevfails = $null

#Connect to the process if already present. It assumes that end with the same id
$pslist = gps powershell -ea 0
if ($pslist -ne $null)
{
    for ($j = 0; $j -lt $count; $j++)
    {
        foreach ($ps in $pslist)
        {
            if ($ps.MainWindowTitle.EndsWith(" $j"))
            {
                "Reusing for index=$j $($ps.ProcessName) with id=$($ps.Id)"
                $proceslist[$j] = $ps
            }
        }
    }
}

while ($true)
{
    for ($j = 0; $j -lt $count; $j++)
    {
        if ($proceslist[$j] -eq 0)
        {
            $proceslist[$j] = Start-Process "$PSHOME\PowerShell.exe" -ArgumentList "-NoProfile -NoExit -f `"$file`" $j" -PassThru
            Write-Verbose "Started $file $j ProcessId=$($proceslist[$j].id)"
            Sleep 1
        }
        elseif ($proceslist[$j] -ne 0) 
        {
            if (-not (Get-Process -id $proceslist[$j].Id -ea 0))
            {
                Write-Verbose "Completed ProcessId=$($proceslist[$j].id)"
                $proceslist[$j] = 0
            }
        <#
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
            #>
        }
    }

    $stat = gstat
    if ($prevstat -ne $stat)
    {
        $stat
        $prevstat = $stat

        $fails = gfail
        foreach ($fail in $fails)
        {
            if (!$prevfails -or !$prevfails.Contains($fail))
            {
                $fail
            }
        }

        $prevfails = $fails
        ''
    }
    Sleep 5
}
return