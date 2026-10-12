# Opt-in diagnostics (/sapi-voice-kit:debug on). With debug off nothing but
# config.json and the duplicate-speech timestamp is written to disk.

$script:LogMaxBytes = 50KB
$script:LogKeepLines = 200

# Returns a scriptblock that appends a timestamped line to $FileName in the
# shared data folder, trimming the file to its last lines once it grows past
# the size cap. When $Enabled is false the scriptblock does nothing.
function Get-Logger {
    param(
        [Parameter(Mandatory)][string]$FileName,
        [bool]$Enabled = $false
    )
    if (-not $Enabled) { return { param([string]$Message) } }

    $path = Join-Path (Initialize-SharedDataDir) $FileName
    $maxBytes = $script:LogMaxBytes
    $keepLines = $script:LogKeepLines
    return {
        param([string]$Message)
        if ((Test-Path $path) -and (Get-Item $path).Length -gt $maxBytes) {
            $tail = Get-Content -Path $path -Tail $keepLines
            Set-Content -Path $path -Value $tail -Encoding UTF8
        }
        Add-Content -Path $path -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message" -Encoding UTF8
    }.GetNewClosure()
}

# Debug aid: keeps a copy of the last text that was spoken.
function Save-LastSpokenText {
    param([Parameter(Mandatory)][string]$Text)
    Set-Content -Path (Join-Path (Initialize-SharedDataDir) 'last-text.txt') -Value $Text -Encoding UTF8
}
