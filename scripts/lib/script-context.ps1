# What every entry script needs at start-up.

# Settings plus a logger that is on only when debug logging is enabled.
function New-ScriptContext {
    param([Parameter(Mandatory)][string]$LogFile)
    $config = Get-VoiceConfig
    $debug = $config.debug -eq $true
    return [pscustomobject]@{
        Config = $config
        Debug  = $debug
        Log    = Get-Logger -FileName $LogFile -Enabled $debug
    }
}

# All of stdin as UTF-8 text. Read as raw bytes because the console's codepage
# would otherwise decode accented characters wrongly. A leading byte-order mark,
# which some writers add, is dropped so it cannot break JSON parsing or leave
# "empty" input looking non-empty.
function Read-StdinUtf8 {
    $buffer = New-Object System.IO.MemoryStream
    [Console]::OpenStandardInput().CopyTo($buffer)
    return [System.Text.Encoding]::UTF8.GetString($buffer.ToArray()).TrimStart([char]0xFEFF)
}
