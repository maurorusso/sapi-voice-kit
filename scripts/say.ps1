# Model-invoked (active mode only): reads short text piped via stdin and
# speaks it immediately, during the same turn - no file, no waiting for the
# Stop hook, no separate AI call. Only meant to run when config.mode is
# "active" - prompt-active-mode.ps1 is what tells the model to call this,
# and in that mode speak.ps1 (the Stop hook) skips speaking entirely so
# the two mechanisms never overlap and produce double audio.

param([string]$PluginData)

. "$PSScriptRoot\common.ps1"

$config = if ($PluginData) { Get-VoiceConfig -PluginData $PluginData } else { $null }
$debugOn = $config -and $config.debug -eq $true
$Log = Get-Logger -PluginData $(if ($debugOn) { $PluginData } else { $null }) -FileName "log-say.txt"

try {
    & $Log "starting (active mode, model-invoked)"

    # Same raw-byte UTF8 stdin read as speak.ps1 - avoids the OEM-codepage
    # decoding bug (see speak.ps1's comments for the full explanation).
    $inputStream = [Console]::OpenStandardInput()
    $buffer = New-Object System.IO.MemoryStream
    $inputStream.CopyTo($buffer)
    $bytes = $buffer.ToArray()
    if ($bytes.Length -eq 0) { & $Log "empty stdin, nothing to say"; exit 0 }
    $text = [System.Text.Encoding]::UTF8.GetString($bytes).Trim()
    if (-not $text) { & $Log "blank text, nothing to say"; exit 0 }
    & $Log "text: $($text.Length) characters"

    if ($debugOn) {
        Set-Content -Path (Join-Path $PluginData "last-text.txt") -Value $text -Encoding UTF8
    }

    Invoke-SpeechSynthesis -Text $text -Config $config -UsePronunciation $true -Log $Log
} catch {
    & $Log "EXCEPTION: $($_.Exception.GetType().Name): $($_.Exception.Message)"
    exit 0
}
