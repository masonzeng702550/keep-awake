<#
.SYNOPSIS
  keep_awake.ps1 — start/stop a scoped Windows keep-awake state.

.DESCRIPTION
  Windows equivalent of the macOS `caffeinate` approach. Uses the Win32
  SetThreadExecutionState API to tell Windows not to sleep while a long task
  runs, then releases the request so normal power-saving resumes.

  Two modes, mirroring the macOS helper:

    start [timeout_seconds]   Hold a keep-awake request in a detached background
                              PowerShell process, with a hard safety cap so an
                              abandoned session can't keep the machine awake
                              forever. Default cap: 3600s (1 hour).
    stop                      Release the request started by `start`.
    status                    Report whether this script is currently holding
                              a keep-awake request.

.NOTES
  - SetThreadExecutionState holds the request only as long as the calling thread
    is alive. That is why `start` spawns a dedicated background process: when it
    is killed (by `stop`) or its timeout elapses, the request is released
    automatically by Windows. No permanent power-plan change is made.
  - ES_CONTINUOUS | ES_SYSTEM_REQUIRED keeps the SYSTEM awake. We deliberately do
    NOT add ES_DISPLAY_REQUIRED, so the screen can still turn off during a
    closed-lid / walk-away run.
  - IMPORTANT lid-close caveat: keeping the system awake is necessary but not
    always sufficient on a laptop. If "When I close the lid" is set to Sleep in
    Windows power settings, closing the lid can still sleep the machine. For a
    reliable closed-lid run, the user should set lid-close action to "Do nothing"
    (Control Panel > Power Options > Choose what closing the lid does), at least
    while plugged in. This script does NOT change that global setting by design;
    it only prevents idle/system sleep for the duration of the task.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('start', 'stop', 'status')]
    [string]$Command,

    [Parameter(Position = 1)]
    [int]$TimeoutSeconds = 3600
)

$ErrorActionPreference = 'Stop'
$PidFile = Join-Path $env:TEMP 'claude_keep_awake.pid'

function Test-Running {
    if (-not (Test-Path $PidFile)) { return $false }
    $procId = Get-Content $PidFile -ErrorAction SilentlyContinue
    if (-not $procId) { return $false }
    return [bool](Get-Process -Id $procId -ErrorAction SilentlyContinue)
}

switch ($Command) {

    'start' {
        if (Test-Running) {
            $existing = Get-Content $PidFile
            Write-Host "keep-awake: already active (pid $existing). Call 'stop' first to restart."
            return
        }
        if ($TimeoutSeconds -le 0) {
            Write-Error "keep-awake: timeout must be a positive number of seconds (got '$TimeoutSeconds')."
            return
        }

        # This script block runs in a detached process. It holds the keep-awake
        # request for the duration, then releases it when the time elapses or the
        # process is killed.
        $worker = @"
`$sig = @'
using System;
using System.Runtime.InteropServices;
public static class Power {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern uint SetThreadExecutionState(uint esFlags);
}
'@
Add-Type -TypeDefinition `$sig
# ES_CONTINUOUS (0x80000000) | ES_SYSTEM_REQUIRED (0x00000001)
[Power]::SetThreadExecutionState([uint32]'0x80000001') | Out-Null
Start-Sleep -Seconds $TimeoutSeconds
# Clear the request explicitly on normal exit (ES_CONTINUOUS only).
[Power]::SetThreadExecutionState([uint32]'0x80000000') | Out-Null
"@

        $bytes = [System.Text.Encoding]::Unicode.GetBytes($worker)
        $encoded = [Convert]::ToBase64String($bytes)

        $proc = Start-Process -FilePath 'powershell.exe' `
            -ArgumentList @('-NoProfile', '-WindowStyle', 'Hidden', '-EncodedCommand', $encoded) `
            -WindowStyle Hidden -PassThru

        Set-Content -Path $PidFile -Value $proc.Id
        $mins = [math]::Round($TimeoutSeconds / 60, 0)
        Write-Host "keep-awake: ON (pid $($proc.Id)), safety cap ${TimeoutSeconds}s (~${mins} min)."
        Write-Host "keep-awake: for a closed-lid run, set lid-close action to 'Do nothing' and stay plugged in. Call 'stop' when the task finishes."
    }

    'stop' {
        if (Test-Running) {
            $procId = Get-Content $PidFile
            Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
            Remove-Item $PidFile -ErrorAction SilentlyContinue
            Write-Host "keep-awake: OFF (released pid $procId). Windows will sleep normally again."
        }
        else {
            Remove-Item $PidFile -ErrorAction SilentlyContinue
            Write-Host "keep-awake: nothing to stop — no active request from this script."
        }
    }

    'status' {
        if (Test-Running) {
            $procId = Get-Content $PidFile
            Write-Host "keep-awake: ACTIVE (pid $procId)."
        }
        else {
            Write-Host "keep-awake: inactive."
        }
        # Surface system-wide power requests for debugging (needs admin to show all).
        Write-Host "--- powercfg /requests (run as admin for full detail) ---"
        try { powercfg /requests } catch { Write-Host "(powercfg unavailable)" }
    }

    default {
        Write-Host "Usage: keep_awake.ps1 {start [timeout_seconds] | stop | status}"
    }
}
