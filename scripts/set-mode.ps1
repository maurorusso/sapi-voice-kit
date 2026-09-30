# Saves the reading mode in config.json: "natural" (full response, cleaned
# for speech), "literal" (full response exactly as written), "summary" (a
# condensed version via a separate `claude -p` call - slower, opt-in), or
# "active" (the model speaks a short paraphrase itself mid-turn - as fast
# and natural as it gets, no waiting on a separate call, but may prompt for
# permission the first time). Works the same way conceptually in the CLI and
# in Claude Cowork/Desktop, just over two different transports depending on
# which one is running - a shell heredoc to say.ps1 in the CLI (reminded by
# prompt-active-mode.ps1's hook), or the read_aloud MCP tool in Cowork
# (reminded by skills/cowork/SKILL.md, since Cowork doesn't fire hooks at
# all) - see mcp-server/server.js and skills/cowork/SKILL.md.

param(
    [Parameter(Mandatory)][string]$PluginData,
    [Parameter(Mandatory)][ValidateSet('natural', 'literal', 'summary', 'active')]
    [string]$Mode,
    [ValidateSet('local', 'cowork')]
    [string]$Namespace = 'local'
)

. "$PSScriptRoot\common.ps1"

Save-VoiceConfig -PluginData $PluginData -Namespace $Namespace -Changes @{ mode = $Mode } | Out-Null
Write-Output "Reading mode: $Mode"
