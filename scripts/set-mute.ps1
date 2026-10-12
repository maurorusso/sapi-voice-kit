# /sapi-voice-kit:mute - silences automatic reading without losing the chosen
# mode. Explicit "read this" requests (say.ps1 -Force) still speak.

param(
    [Parameter(Mandatory)][ValidateSet('on', 'off')]
    [string]$State
)

. "$PSScriptRoot\common.ps1"

Save-VoiceConfig -Changes @{ muted = ($State -eq 'on') } | Out-Null
Write-Output "Muted: $State"
