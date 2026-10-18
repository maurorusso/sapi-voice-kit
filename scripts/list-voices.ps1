# Lists every voice the plugin can use, from both engines (modern OneCore
# voices and classic SAPI5 ones), and which one is being used right now.

. "$PSScriptRoot\common.ps1"

$voices = @(Get-InstalledVoices)

$voices |
    Select-Object @{ Name = 'Engine'; Expression = { if ($_.Engine -eq 'OneCore') { 'OneCore (moderna)' } else { 'SAPI5 (clásica)' } } }, Name, Language, Gender |
    Format-Table -AutoSize

$active = Resolve-SpeechTarget -Config (Get-VoiceConfig) -Voices $voices
$activeName = if ($active.Name) { $active.Name } else { 'voz predeterminada del sistema' }
Write-Output "Se está usando ahora ($(Get-ConfigNamespace)): $activeName ($($active.Engine))"
