# Turns diagnostic logging on/off. Off by default: with debug off, this
# plugin writes nothing to its data folder besides your own explicit
# settings (config.json) - no log files, no copy of what was spoken.

param(
    [Parameter(Mandatory)][string]$PluginData,
    [Parameter(Mandatory)][ValidateSet('on', 'off')]
    [string]$State
)

. "$PSScriptRoot\common.ps1"

Save-VoiceConfig -PluginData $PluginData -Changes @{ debug = ($State -eq 'on') } | Out-Null
Write-Output "Debug logging: $State"
