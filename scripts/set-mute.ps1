# Turns automatic reading on/off machine-wide, without touching the chosen
# mode. Separate from `mode` on purpose: muting and unmuting shouldn't make
# you re-pick natural/literal/summary/active each time - it's a pause, not a
# reconfiguration. Checked first thing in speak.ps1, say.ps1, and
# prompt-active-mode.ps1, before any other logic. Does NOT block the
# on-demand "read this" skill, which passes -Force to say.ps1 - muting the
# automatic reader shouldn't stop you from asking for a reading explicitly.

param(
    [Parameter(Mandatory)][string]$PluginData,
    [Parameter(Mandatory)][ValidateSet('on', 'off')]
    [string]$State
)

. "$PSScriptRoot\common.ps1"

Save-VoiceConfig -PluginData $PluginData -Changes @{ muted = ($State -eq 'on') } | Out-Null
Write-Output "Muted: $State"
