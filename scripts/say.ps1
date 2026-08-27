# Model-invoked: reads short text piped via stdin and speaks it immediately -
# no file, no waiting for the Stop hook, no separate AI call. Two callers:
# - prompt-active-mode.ps1's instruction, every turn, when config.mode is
#   "active" (speak.ps1, the Stop hook, skips speaking entirely in that mode
#   so the two mechanisms never overlap and produce double audio).
# - the "read this" skill, on demand, whenever the user explicitly asks to
#   hear something read - passes -Force so an explicit request still works
#   even while muted (mute only silences the automatic per-turn reading).

param([string]$PluginData, [switch]$Force)

. "$PSScriptRoot\common.ps1"

$config = if ($PluginData) { Get-VoiceConfig -PluginData $PluginData } else { $null }
$debugOn = $config -and $config.debug -eq $true
$Log = Get-Logger -PluginData $(if ($debugOn) { $PluginData } else { $null }) -FileName "log-say.txt"

try {
    & $Log "starting (Force=[$Force])"

    # Same raw-byte UTF8 stdin read as speak.ps1 - avoids the OEM-codepage
    # decoding bug (see speak.ps1's comments for the full explanation).
    #
    # Read fully before checking $muted (below) so stdin is always drained,
    # even when muted and not forced - whatever invoked this script may be
    # doing a blocking write of the full payload and not expect the child to
    # exit before reading any of it.
    $inputStream = [Console]::OpenStandardInput()
    $buffer = New-Object System.IO.MemoryStream
    $inputStream.CopyTo($buffer)
    $bytes = $buffer.ToArray()

    if (-not $Force -and $config -and $config.muted -eq $true) {
        & $Log "muted and not forced, exiting"
        exit 0
    }
    if ($bytes.Length -eq 0) { & $Log "empty stdin, nothing to say"; exit 0 }
    $text = [System.Text.Encoding]::UTF8.GetString($bytes).Trim()
    if (-not $text) { & $Log "blank text, nothing to say"; exit 0 }
    & $Log "text: $($text.Length) characters"

    # Safety net, not the primary fix: the instructions this script's callers
    # give the model (prompt-active-mode.ps1, read-last/SKILL.md) already ask
    # it to write "punto" instead of a literal "." before a file extension -
    # but that's a written instruction, not a guarantee, and this project
    # doesn't rely on the model remembering things it's asked to do every
    # time (see active mode's own known weakness). Idempotent either way: a
    # no-op if the model already wrote "punto" (no literal dot pattern left
    # to match), a real fix if it didn't.
    $text = ConvertTo-SpokenFileNames -Text $text
    $text = ConvertTo-SpokenUrls -Text $text

    if ($debugOn) {
        Set-Content -Path (Join-Path $PluginData "last-text.txt") -Value $text -Encoding UTF8
    }

    Invoke-SpeechSynthesis -Text $text -Config $config -UsePronunciation $true -Log $Log
} catch {
    & $Log "EXCEPTION: $($_.Exception.GetType().Name): $($_.Exception.Message)"
    exit 0
}
