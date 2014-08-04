function WinEC2LoopRunOne
{
    param ($file, $count, $retryCount, [Hashtable]$parameterSet)
    $failures = 0

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

    $paramstring = ''
    foreach ($key in $parameterSet.Keys)
    {
        $value = $parameterSet[$key]
        $paramstring += "`t$key=$value"
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

            $stRunning = "{0:mm\:ss}" -f $a.Time.Running
            $stPing = "{0:mm\:ss}" -f $a.Time.Ping
            $stPassword = "{0:mm\:ss}" -f $a.Time.Password
            $stRemote = "{0:mm\:ss}" -f $a.Time.Remote

            "$i`t$stRunning`t$stPing`t$stPassword`t$stRemote`tFailures=$failures$paramstring" >> $file
            $i++
            log "Number=$i, Failures=$failures Max retry=$RetryCount New-WinEC2Instance $($a.instanceid) completed"
            Remove-WinEC2Instance $a.instanceid 
            log "Remove-WinEC2Instance $($a.instanceid) completed"
            $a = $null
        }
        catch
        {
            $failures++
            logexception $_.Exception
            log "Failures=$failures Max retry=$RetryCount, Instanceid=$($a.instanceid)"
        }
        if ($failures -ge $retryCount)
        {
            log "Max retry reached (RetrCount=$RetryCount), so will exit now"
            break
        }
    }

    if ($sumcount -gt 0)
    {
        $sumRunning = New-TimeSpan -Seconds ($sumRunning.TotalSeconds/$sumcount)
        $sumPing = New-TimeSpan -Seconds ($sumPing.TotalSeconds/$sumcount)
        $sumPassword = New-TimeSpan -Seconds ($sumPassword.TotalSeconds/$sumcount)
        $sumRemote = New-TimeSpan -Seconds ($sumRemote.TotalSeconds/$sumcount)
        "SUM`t$sumRunning`t$sumPing`t$sumPassword`t$sumRemote`tFailures=$failures$paramstring" >> $file
    }
}