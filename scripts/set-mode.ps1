# /sapi-voice-kit:mode - saves how responses are read:
#   natural  the whole response, markdown removed
#   literal  the whole response exactly as written
#   summary  a short summary (adds ~20 s per response)
#   active   the model speaks a short paraphrase itself, mid-turn

param(
    [Parameter(Mandatory)][ValidateSet('natural', 'literal', 'summary', 'active')]
    [string]$Mode
)

. "$PSScriptRoot\common.ps1"

Save-VoiceConfig -Changes @{ mode = $Mode } | Out-Null
Write-Output "Reading mode: $Mode"
