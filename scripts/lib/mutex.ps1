# Cross-process locking shared by the config store and the speech engines.

# Runs $Action while holding a machine-wide named mutex and returns whatever
# $Action returns. "Local\" names are scoped to one Windows session, which is
# enough here (every process belongs to the same desktop user) and needs no
# elevated privilege, unlike "Global\".
#
# If the wait times out the action runs anyway: a stuck or crashed holder must
# never freeze or silence every other process.
function Invoke-WithNamedMutex {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$TimeoutMs,
        [Parameter(Mandatory)][scriptblock]$Action,
        [scriptblock]$Log = { param([string]$Message) }
    )

    $mutex = New-Object System.Threading.Mutex($false, $Name)
    $acquired = $false
    try {
        try {
            $acquired = $mutex.WaitOne($TimeoutMs)
        } catch [System.Threading.AbandonedMutexException] {
            # The previous holder exited without releasing; the mutex is ours now.
            $acquired = $true
        }
        if (-not $acquired) {
            & $Log "timed out after ${TimeoutMs}ms waiting for $Name; continuing without the lock"
        }
        & $Action
    } finally {
        if ($acquired) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}
