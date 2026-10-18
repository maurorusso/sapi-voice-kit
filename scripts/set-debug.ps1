# /sapi-voice-kit:debug - turns diagnostic logging on or off. Off by default:
# with it off, nothing but config.json and a timestamp is written to disk, and
# turning it off deletes what debug had written.

param(
    [Parameter(Mandatory)][ValidateSet('on', 'off')]
    [string]$State
)

. "$PSScriptRoot\common.ps1"

Save-VoiceConfig -Changes @{ debug = ($State -eq 'on') } | Out-Null
if ($State -eq 'off') { Remove-DebugFiles }
Write-Output "Debug logging: $State"
