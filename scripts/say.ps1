# Speaks the text piped in on stdin, right away. Callers:
#  - the model, every turn in "active" mode, through prompt-active-mode.ps1's
#    instruction (the Stop hook stays silent in that mode so audio never doubles);
#  - the MCP read_aloud tool (Cowork), which spawns this script;
#  - the read-last skill, with -Force, for an explicit "read this".
#
# -Force bypasses mute and the duplicate-speech guard. -RequireMode makes the
# script do nothing unless the configured mode matches; the MCP server uses it
# so the mode check lives here, in one place. The script always prints one
# status line ("Spoken." or "Not spoken: <reason>") so the caller can tell the
# model what happened.

param(
    [switch]$Force,
    [ValidateSet('natural', 'literal', 'summary', 'active')]
    [string]$RequireMode
)

. "$PSScriptRoot\common.ps1"

$context = New-ScriptContext -LogFile 'log-say.txt'
$Log = $context.Log

try {
    # Read stdin completely even when about to exit, so the writer never blocks.
    $text = (Read-StdinUtf8).Trim()

    if (-not $Force -and $context.Config.muted -eq $true) { & $Log 'muted'; Write-Output 'Not spoken: sapi-voice-kit is muted.'; exit 0 }
    if ($RequireMode -and -not $Force -and $context.Config.mode -ne $RequireMode) {
        Write-Output "Not spoken: sapi-voice-kit is not in '$RequireMode' mode."
        exit 0
    }
    if (-not $text) { & $Log 'nothing to say'; Write-Output 'Not spoken: the text was empty.'; exit 0 }

    # The model is asked to write file names and links the way they should be
    # spoken, but a written instruction is not a guarantee: normalize anyway
    # (a no-op on text that is already clean).
    $text = ConvertTo-SpokenUrls -Text $text
    $text = ConvertTo-SpokenIdentifiers -Text $text

    if (-not $Force -and (Test-RecentActiveSpeech)) {
        & $Log 'duplicate of an utterance just spoken, skipping'
        Write-Output 'Not spoken: this turn was already spoken.'
        exit 0
    }

    if ($context.Debug) { Save-LastSpokenText -Text $text }
    Invoke-SpeechSynthesis -Text $text -Config $context.Config -Log $Log
    if (-not $Force) { Set-RecentSpeechMarker }
    Write-Output 'Spoken.'
} catch {
    & $Log "EXCEPTION: $($_.Exception.Message)"
    Write-Output 'Not spoken: an error occurred (turn on /sapi-voice-kit:debug to see why).'
    exit 0
}
