﻿function IgnoreError ($scriptBlock)
{
    try
    {
        . $scriptBlock
    }
    catch
    {
    }
}

function RetryOnError ($scriptBlock, $retryCount = 3)
{
    for ($i=1; $i -le $retryCount; $i++)
    {
        try
        {
            . $scriptBlock
            break
        }
        catch
        {
            Write-Host "Error: $($_.Exception.Message), RetryCount=$i, ScriptBlock=$scriptBlock" -ForegroundColor Yellow
            if ($i -eq $retryCount)
            {
                throw $_.Execption
            }
            Sleep 10 # wait before retrying
        }
    }
}

function GetString ($obj)
{
    $st = ''
    foreach ($key in $obj.Keys)
    {
        if ($obj[$key] -is [Timespan])
        {
            $value = '{0:hh\:mm\:ss}' -f $obj."$key"
        }
        else
        {
            $value = [string]$obj[$key]
        }
        $st = "$st`t$key=$value"
    }
    $st
}

function Log ()
{
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline=$true)]
        [string]$st
    )
    PROCESS {
        $message = "$((Get-date).ToLongTimeString()) $st"
        Write-Host $message
        $message >> $logfile
    }
}

function LogStat ($message)
{
    RetryOnError {$message >> $logStatFile}
    Log $message
    Write-Host ''
}

function RandomPick ([string[]] $list)
{
    $list[(Get-Random $list.Count)]
}


function RunTest ([string[]] $Tests, [string]$OnError)
{
    del $logfile -ea 0
    try
    {
        foreach ($test in $Tests)
        {
            #$tinfo = gcm $test
            #$tinfo.ScriptBlock.Attributes

            Log "Start $test $(GetString $obj)"
            . $test 4>&1 3>&1 5>&1 | Log
            Log "End $test $(GetString $obj)"
        }

        LogStat "SUCCESS: $(GetString $obj)"
    }
    catch
    {
        LogStat "Fail: Message=$($_.Exception.Message), $(GetString $obj)"
        $ex = $_.Exception

        if ($OnError -ne $null)
        {
            Log ''
            Log ''
            Log 'OnError Dump'
            try
            {
                . $OnError 4>&1 3>&1 5>&1 | Log
            }
            catch
            {
                Log "OnError: Message=$($_.Exception.Message)"
            }
        }

        throw $ex
    }
}

function RandomTestLoop (
        [string[]] $Tests,
        [Hashtable]$Parameters,
        [string]$OnError,
        [int]$MaxCount = 1000
    )
{
    $logfile = "$name.log"
    $global:obj = New-Object 'system.collections.generic.dictionary[[string],[object]]'
    $obj.Add('Name', $name)
    $obj.Add('Count', 0)

    while ($true)
    {
        foreach ($key in $parameters.keys)
        {
            $obj.$key = RandomPick $parameters.$key
        }
        $obj.Count++
        #'BreakIt', 'ChangeInstanceTypes'
        RunTest -Tests $tests -OnError $OnError

        if ($obj.Count -ge $MaxCount)
        {
            break
        }
        gstat
    }
}