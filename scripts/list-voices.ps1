# Lists every speech-synthesis voice this plugin can use (to pick one with
# /sapi-voice-kit:voice) - both engines: modern OneCore natural voices
# (preferred by default when one exists for your language - see
# Resolve-SpeechTarget in common.ps1) and the classic SAPI5 Desktop voices
# every Windows install has. Shows which engine each row belongs to, since
# the same display name never appears under both.

param([string]$PluginData)

. "$PSScriptRoot\common.ps1"

$rows = @()

$rows += Get-OneCoreVoices | ForEach-Object {
    [PSCustomObject]@{
        Engine   = 'OneCore (moderna)'
        Name     = $_.DisplayName
        Language = $_.Language
        Gender   = $_.Gender
    }
}

Add-Type -AssemblyName System.Speech
$sapiSynth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$rows += $sapiSynth.GetInstalledVoices() | Where-Object { $_.Enabled } | ForEach-Object {
    [PSCustomObject]@{
        Engine   = 'SAPI5 (clasica)'
        Name     = $_.VoiceInfo.Name
        Language = $_.VoiceInfo.Culture.Name
        Gender   = $_.VoiceInfo.Gender
    }
}

$rows | Format-Table -AutoSize

if ($PluginData) {
    $config = Get-VoiceConfig -PluginData $PluginData
    $target = Resolve-SpeechTarget -Config $config
    $activeName = if ($target.Engine -eq 'OneCore') { $target.Voice.DisplayName } else { $target.VoiceName }
    Write-Output "Se está usando ahora: $activeName ($($target.Engine))"
}
