# Saves the reading mode in config.json: "natural" (full response, cleaned
# for speech), "literal" (full response exactly as written), "summary" (a
# condensed version via a separate `claude -p` call - slower, opt-in), or
# "active" (the model speaks a short paraphrase itself mid-turn - fastest
# and most natural, but may prompt for permission the first time).

param(
    [Parameter(Mandatory)][string]$PluginData,
    [Parameter(Mandatory)][ValidateSet('natural', 'literal', 'summary', 'active')]
    [string]$Mode
)

. "$PSScriptRoot\common.ps1"

Save-VoiceConfig -PluginData $PluginData -Changes @{ mode = $Mode } | Out-Null
Write-Output "Reading mode: $Mode"
