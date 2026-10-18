# Duplicate-speech guard.
#
# In "active" mode the same turn can be spoken twice: once by the CLI's heredoc
# command and once by the MCP read_aloud tool (both reach say.ps1, and the MCP
# server is also registered inside CLI sessions). say.ps1 records when it last
# claimed the right to speak and skips a non-forced utterance that arrives
# within a few seconds of the previous claim. Only a timestamp is stored, never
# the text, and it is deliberately not per-namespace: its job is to deduplicate
# across them.

$script:SpeechGuardWindowSeconds = 8

function Test-RecentActiveSpeech {
    $path = Get-DataFilePath '.last-active-speech'
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    try {
        $lastTicks = [long](Get-Content -LiteralPath $path -Raw -Encoding UTF8 -ErrorAction Stop).Trim()
        $elapsed = [DateTime]::UtcNow.Ticks - $lastTicks
        # A marker dated in the future (clock set back) is not a recent speech.
        return $elapsed -ge 0 -and $elapsed -le [TimeSpan]::FromSeconds($script:SpeechGuardWindowSeconds).Ticks
    } catch {
        # An unreadable marker must never block speech.
        return $false
    }
}

function Set-RecentSpeechMarker {
    try {
        $path = Join-Path (Initialize-SharedDataDir) '.last-active-speech'
        "$([DateTime]::UtcNow.Ticks)" | Set-Content -LiteralPath $path -Encoding UTF8 -ErrorAction Stop
    } catch {
        # Best effort: a marker that cannot be written only means a duplicate may be spoken.
    }
}

# Gives the claim back when speaking failed, so a retry is not turned away as a
# duplicate of an utterance nobody heard.
function Clear-RecentSpeechMarker {
    Remove-Item -LiteralPath (Get-DataFilePath '.last-active-speech') -Force -ErrorAction SilentlyContinue
}

# Decides whether a non-forced utterance may be spoken: false when another one
# claimed the right within the window, otherwise it claims it now. The check and
# the claim happen under one lock, so two callers that arrive together cannot both
# pass. Not called for -Force (an explicit "read this" request): it must not make
# the next automatic utterance look like a duplicate.
function Request-ActiveSpeech {
    return Invoke-WithNamedMutex -Name $script:ConfigLockName -TimeoutMs $script:ConfigLockTimeoutMs -Action {
        if (Test-RecentActiveSpeech) { return $false }
        Set-RecentSpeechMarker
        return $true
    }
}
