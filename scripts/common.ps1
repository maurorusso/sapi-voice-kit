# Entry point shared by every script: dot-source this file, and the whole
# library is available. The code lives in lib/, one file per concern.

# Scripts write their results to stdout and the MCP server reads them as UTF-8.
# PowerShell 5.1 would otherwise write in the console's OEM codepage and
# accented text would arrive garbled. No BOM, so the first line stays clean.
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

. "$PSScriptRoot\lib\mutex.ps1"
. "$PSScriptRoot\lib\config.ps1"
. "$PSScriptRoot\lib\speech-guard.ps1"
. "$PSScriptRoot\lib\logging.ps1"
. "$PSScriptRoot\lib\script-context.ps1"
. "$PSScriptRoot\lib\text-normalization.ps1"
. "$PSScriptRoot\lib\speech-rate.ps1"
. "$PSScriptRoot\lib\pronunciation.ps1"
. "$PSScriptRoot\lib\engine-onecore.ps1"
. "$PSScriptRoot\lib\engine-sapi5.ps1"
. "$PSScriptRoot\lib\voices.ps1"
. "$PSScriptRoot\lib\speech.ps1"
. "$PSScriptRoot\lib\spoken-text-prompt.ps1"
. "$PSScriptRoot\lib\test-sentence.ps1"
