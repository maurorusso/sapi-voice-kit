# Duplicate-speech guard.
#
# In "active" mode the same turn can be spoken twice: once by the CLI's heredoc
# command and once by the MCP read_aloud tool (both reach say.ps1, and the MCP
# server is also registered inside CLI sessions). say.ps1 records when it last
# spoke and skips a non-forced utterance that arrives within a few seconds of
# the previous one. Only a timestamp is stored, never the text, and it is
# deliberately not per-namespace: its job is to deduplicate across them.

$script:SpeechGuardWindowSeconds = 8

function Test-RecentActiveSpeech {
    $path = Get-DataFilePath '.last-active-speech'
    if (-not (Test-Path $path)) { return $false }
    try {
        $lastTicks = [long](Get-Content -Path $path -Raw -Encoding UTF8).Trim()
        $elapsed = (Get-Date).Ticks - $lastTicks
        return $elapsed -le [TimeSpan]::FromSeconds($script:SpeechGuardWindowSeconds).Ticks
    } catch {
        # An unreadable marker must never block speech.
        return $false
    }
}

# Not called for -Force (an explicit "read this" request): it must not make the
# next automatic utterance look like a duplicate.
function Set-RecentSpeechMarker {
    try {
        $path = Join-Path (Initialize-SharedDataDir) '.last-active-speech'
        "$((Get-Date).Ticks)" | Set-Content -Path $path -Encoding UTF8
    } catch {
        # Best effort: the speech already happened.
    }
}
