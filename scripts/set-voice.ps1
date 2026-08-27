# Saves the voice/language/rate override in config.json (persists across plugin updates).
# -Auto clears the voice/language override and goes back to automatic detection
# by system language. Mode and rate, if set, are left untouched either way.

param(
    [Parameter(Mandatory)][string]$PluginData,
    [string]$Voice,
    [string]$Language,
    [int]$Rate = [int]::MinValue,
    [switch]$Auto
)

. "$PSScriptRoot\common.ps1"

if ($Rate -ne [int]::MinValue -and ($Rate -lt -10 -or $Rate -gt 10)) {
    Write-Output "Rate must be between -10 and 10 (that's the range Windows speech synthesis accepts). Got: $Rate"
    exit 1
}

if ($Auto) {
    Save-VoiceConfig -PluginData $PluginData -Remove @('voiceName', 'language') | Out-Null
    Write-Output "Automatic mode: the system language will be detected again on every response."
} else {
    $changes = @{}
    $remove = @()
    if ($Voice) { $changes.voiceName = $Voice; $remove += 'language' }
    if ($Language) { $changes.language = $Language; $remove += 'voiceName' }
    if ($Rate -ne [int]::MinValue) { $changes.rate = $Rate }

    $updated = Save-VoiceConfig -PluginData $PluginData -Changes $changes -Remove $remove
    Write-Output "Saved:"
    $updated | ConvertTo-Json
}
