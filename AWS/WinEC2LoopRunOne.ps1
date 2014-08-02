function WinEC2LoopRunOne
{
    param ($file, $count, $retryCount, [Hashtable]$parameterSet)

    function log ([string]$st)
    {
        $time = (Get-date).ToLongTimeString()
        "$time - $st" | tee -FilePath $logfile -Append
    }

    function logexception ([Exception] $exception)
    {
        log 'Exception:'
        log $exception.ToString()
    }

    $logfile = $file.Replace('.csv', '.log')

    del $logfile -ea 0
    del $file -ea 0

    'New Parameter Set'>> $file

    foreach ($key in $parameterSet.Keys)
    {
        $value = $parameterSet[$key]
        "    $key=$value">> $file
    }

    "Count`tRunning`tPing`tPassword`tRemote" >> $file
    $sumRunning = $sumPing = $sumPassword = $sumRemote =0
    $sumcount = 0
    for($i=0; $i -lt $Count; )
    {
        try
        {
            $a = New-WinEC2Instance @parameterSet
            $sumRunning += $a.Time.Running
            $sumPing += $a.Time.Ping
            $sumPassword += $a.Time.Password
            $sumRemote += $a.Time.Remote
            $sumcount++
            "$i`t$($a.Time.Running)`t$($a.Time.Ping)`t$($a.Time.Password)`t$($a.Time.Remote)" >> $file
            $i++
            log "Number=$i, Retries left=$RetryCount New-WinEC2Instance $($a.instanceid) completed"
            Remove-WinEC2Instance $a.instanceid 
            log "Remove-WinEC2Instance $($a.instanceid) completed"
            $a = $null
        }
        catch
        {
            $retryCount--
            logexception $_.Exception
            log "Retries left = $RetryCount, Instanceid=$($a.instanceid)"
        }
        if ($retryCount -le 0)
        {
            log "Max retry reached, so will exit now"
            break
        }
    }

    if ($sumcount -gt 0)
    {
        $sumRunning = New-TimeSpan -Seconds ($sumRunning.TotalSeconds/$sumcount)
        $sumPing = New-TimeSpan -Seconds ($sumPing.TotalSeconds/$sumcount)
        $sumPassword = New-TimeSpan -Seconds ($sumPassword.TotalSeconds/$sumcount)
        $sumRemote = New-TimeSpan -Seconds ($sumRemote.TotalSeconds/$sumcount)
        "SUM`t$sumRunning`t$sumPing`t$sumPassword`t$sumRemote" >> $file
    }
}