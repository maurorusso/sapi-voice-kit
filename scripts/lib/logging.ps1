# Opt-in diagnostics (/sapi-voice-kit:debug on). With debug off nothing but
# config.json and the duplicate-speech timestamp is written to disk.

$script:LogMaxBytes = 50KB
$script:LogKeepLines = 200

# Returns a scriptblock that appends a timestamped line to $FileName in the
# shared data folder, trimming the file to its last lines once it grows past
# the size cap. When $Enabled is false the scriptblock does nothing.
function Get-Logger {
    param(
        [Parameter(Mandatory)][string]$FileName,
        [bool]$Enabled = $false
    )
    if (-not $Enabled) { return $script:SilentLog }

    $path = Join-Path (Initialize-SharedDataDir) $FileName
    $maxBytes = $script:LogMaxBytes
    $keepLines = $script:LogKeepLines
    return {
        param([string]$Message)
        # Best effort, on purpose: two processes may log at once and an antivirus may hold the
        # file, and a diagnostic line must never stop the speech. The mutex only makes that rare.
        # It is taken here and not through Invoke-WithNamedMutex, which a closure cannot see.
        $mutex = New-Object System.Threading.Mutex($false, 'Local\SapiVoiceKitLog')
        $held = $false
        try {
            try { $held = $mutex.WaitOne(2000) } catch [System.Threading.AbandonedMutexException] { $held = $true }
            if ((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).Length -gt $maxBytes) {
                $tail = Get-Content -LiteralPath $path -Tail $keepLines -ErrorAction Stop
                Set-Content -LiteralPath $path -Value $tail -Encoding UTF8 -ErrorAction Stop
            }
            Add-Content -LiteralPath $path -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message" -Encoding UTF8 -ErrorAction Stop
        } catch { $null = $_ } finally {
            if ($held) { $mutex.ReleaseMutex() }
            $mutex.Dispose()
        }
    }.GetNewClosure()
}

# Debug aid: keeps a copy of the last text that was spoken. Best effort: a copy that cannot be
# written (open in another program) is logged and must not stop the speech.
function Save-LastSpokenText {
    param(
        [Parameter(Mandatory)][string]$Text,
        [scriptblock]$Log = $script:SilentLog
    )
    try { Set-Content -LiteralPath (Join-Path (Initialize-SharedDataDir) 'last-text.txt') -Value $Text -Encoding UTF8 -ErrorAction Stop }
    catch { & $Log "could not save the copy of the text: $($_.Exception.Message)" }
}

# Turning debug off must leave nothing readable behind: the copy of the last
# text and the log files go. Only these names are touched, never the config.
function Remove-DebugFiles {
    $dir = Get-SharedDataDir
    if (-not (Test-Path -LiteralPath $dir)) { return }
    # A file that cannot be deleted (open in another program) is an error, not a success:
    # the caller must not report debug as off while the text is still there.
    $failed = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -eq 'last-text.txt' -or $_.Name -like 'log-*.txt' })) {
        try { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop } catch { $failed += $file.Name }
    }
    if ($failed) { throw "Could not delete the debug files: $($failed -join ', ')" }
}
