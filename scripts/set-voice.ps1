# /sapi-voice-kit:voice - saves the voice, language or speaking rate.
#   -Voice "<name>"   a specific installed voice (see list-voices.ps1)
#   -Language "es-MX" the best voice for a language
#   -Rate -10..10     slower .. faster
#   -Auto             back to automatic detection from the system language
# -Voice and -Language replace each other; rate is independent of both.

param(
    [string]$Voice,
    [string]$Language,
    [ValidateRange(-10, 10)]
    [Nullable[int]]$Rate,
    [switch]$Auto
)

. "$PSScriptRoot\common.ps1"

$rateGiven = $null -ne $Rate

if ($Auto -and ($Voice -or $Language -or $rateGiven)) {
    Write-Output '-Auto clears the voice and language by itself; give it alone.'
    exit 1
}
if ($Auto) {
    Save-VoiceConfig -Remove @('voiceName', 'language') | Out-Null
    Write-Output 'Automatic mode: the voice follows the system language.'
    exit 0
}
if ($Voice -and $Language) {
    Write-Output 'Give either -Voice or -Language, not both: a named voice already fixes the language.'
    exit 1
}
if (-not ($Voice -or $Language -or $rateGiven)) {
    Write-Output 'Nothing to change: give -Voice, -Language, -Rate or -Auto.'
    exit 1
}

$changes = @{}
$remove = @()
if ($Voice) { $changes.voiceName = $Voice; $remove += 'language' }
if ($Language) { $changes.language = $Language; $remove += 'voiceName' }
if ($rateGiven) { $changes.rate = $Rate }

$saved = Save-VoiceConfig -Changes $changes -Remove $remove
Write-Output 'Saved:'
$saved | ConvertTo-Json
# Find-Voice falls back to an automatic voice, so it cannot say whether the name exists.
if ($Voice -and -not (@(Get-InstalledVoices) | Where-Object { $_.Name -eq $Voice })) {
    Write-Output "Warning: no installed voice is named '$Voice' (see /sapi-voice-kit:voice); the automatic voice choice applies until it is installed."
}
