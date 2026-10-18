# Settings storage: where the plugin keeps its data and how it reads/writes
# config.json.
#
# Every install of the plugin on this Windows account (CLI, Desktop's Code tab,
# Cowork) shares one data folder, so a setting changed from one place is seen
# by the others. config.json holds one independent section per environment:
#
#   { "local": { "mode": "active", ... }, "cowork": { ... } }
#
#   local  - everything started by Claude Code's hooks. The CLI and the Code tab
#            fire identical hooks, so they cannot be told apart and share it.
#   cowork - everything that arrives through the MCP server, the only way
#            Cowork can reach this plugin.
#
# The section a process uses comes from SAPI_VOICE_NAMESPACE (the MCP server
# sets it to "cowork" when it spawns a script); without it, "local".
#
# SAPI_VOICE_DATA_DIR, when set, replaces the data folder. The tests and the
# self-test use it to work in a throwaway folder without touching the real one.

$script:ConfigNamespaces = @('local', 'cowork')
$script:ConfigLockName = 'Local\SapiVoiceKitConfig'
$script:ConfigLockTimeoutMs = 5000

function Get-SharedDataDir {
    if ($env:SAPI_VOICE_DATA_DIR) { return $env:SAPI_VOICE_DATA_DIR }
    return Join-Path $env:USERPROFILE '.claude\plugins\data\sapi-voice-kit-shared'
}

# Path of a file inside the shared folder. Does not create anything.
function Get-DataFilePath {
    param([Parameter(Mandatory)][string]$Name)
    return Join-Path (Get-SharedDataDir) $Name
}

# Creates the shared folder if needed and returns its path. Call before writing.
function Initialize-SharedDataDir {
    $dir = Get-SharedDataDir
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Assert-ConfigNamespace {
    param([Parameter(Mandatory)][string]$Namespace)
    if ($script:ConfigNamespaces -notcontains $Namespace) {
        throw "Unknown config namespace '$Namespace' (expected one of: $($script:ConfigNamespaces -join ', '))"
    }
}

function Get-ConfigNamespace {
    $name = if ($env:SAPI_VOICE_NAMESPACE) { $env:SAPI_VOICE_NAMESPACE } else { 'local' }
    Assert-ConfigNamespace $name
    return $name
}

# Shallow copy of a parsed JSON object into an editable hashtable.
function ConvertTo-Hashtable {
    param($InputObject)
    $result = @{}
    if ($InputObject) {
        foreach ($property in $InputObject.psobject.Properties) { $result[$property.Name] = $property.Value }
    }
    return $result
}

# Whole config.json as { namespace = settings-hashtable }. A missing file is an
# empty config. I/O errors propagate as they are; content that is not valid JSON
# throws a FormatException, so callers can tell a damaged file from a busy one.
function Read-ConfigRoot {
    param([Parameter(Mandatory)][string]$Path)
    $root = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $root }
    $text = [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding($false)))
    try {
        $parsed = $text | ConvertFrom-Json
    } catch {
        throw (New-Object System.FormatException("config.json is not valid JSON: $($_.Exception.Message)"))
    }
    # A JSON list or a bare value is not a config. The full type name is used because
    # [pscustomobject] is PowerShell's PSObject, which a parsed list or number also is.
    if ($null -ne $parsed -and $parsed -isnot [System.Management.Automation.PSCustomObject]) {
        throw (New-Object System.FormatException('config.json must hold a JSON object'))
    }
    foreach ($section in $parsed.psobject.Properties) {
        if ($null -ne $section.Value -and $section.Value -isnot [System.Management.Automation.PSCustomObject]) {
            throw (New-Object System.FormatException("config.json section '$($section.Name)' must be a JSON object"))
        }
        $root[$section.Name] = ConvertTo-Hashtable $section.Value
    }
    return $root
}

# Writes through a temp file and a rename so a reader never sees a half-written
# config.json.
function Write-ConfigRoot {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Root
    )
    $temp = "$Path.tmp"
    $json = $Root | ConvertTo-Json -Depth 5
    try {
        [System.IO.File]::WriteAllText($temp, $json, (New-Object System.Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $Path) {
            [System.IO.File]::Replace($temp, $Path, [NullString]::Value)
        } else {
            Move-Item -LiteralPath $temp -Destination $Path -ErrorAction Stop
        }
    } finally {
        # Only the save error matters: a temp file that cannot be deleted is overwritten by the next save.
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
}

# Settings of one namespace. Never returns $null: if the file is missing or
# unreadable, the defaults apply, so a damaged config cannot silence the hooks.
# (An unknown namespace is a caller bug and does throw.)
function Get-VoiceConfig {
    param([string]$Namespace = (Get-ConfigNamespace))
    Assert-ConfigNamespace $Namespace

    $path = Get-DataFilePath 'config.json'
    try {
        $root = Invoke-WithNamedMutex -Name $script:ConfigLockName -TimeoutMs $script:ConfigLockTimeoutMs -Action {
            Read-ConfigRoot -Path $path
        }
    } catch {
        return @{}
    }
    if ($root.Contains($Namespace)) { return $root[$Namespace] }
    return @{}
}

# Applies $Changes and $Remove to one namespace, leaves the others untouched,
# and returns that namespace's new settings. A config.json that is not valid
# JSON is moved to config.json.bad and replaced, rather than written back
# half-understood; an I/O error (a file locked by a scanner, say) propagates and
# leaves the file alone.
function Save-VoiceConfig {
    param(
        [string]$Namespace = (Get-ConfigNamespace),
        [hashtable]$Changes = @{},
        [string[]]$Remove = @()
    )
    Assert-ConfigNamespace $Namespace

    # Any failure on the way (reading a locked file, moving a damaged one aside, writing)
    # must end the calling script with an error: a .NET exception raised by a method call
    # only ends its own statement, and the script would go on to report a setting that
    # was never saved.
    try {
        $path = Join-Path (Initialize-SharedDataDir) 'config.json'
        return Invoke-WithNamedMutex -Name $script:ConfigLockName -TimeoutMs $script:ConfigLockTimeoutMs -Action {
            try {
                $root = Read-ConfigRoot -Path $path
            } catch [System.FormatException] {
                Move-Item -LiteralPath $path -Destination "$path.bad" -Force -ErrorAction Stop
                $root = @{}
            }

            $settings = if ($root.Contains($Namespace)) { $root[$Namespace] } else { @{} }
            foreach ($change in $Changes.GetEnumerator()) { $settings[$change.Name] = $change.Value }
            foreach ($setting in $Remove) { $settings.Remove($setting) }
            $root[$Namespace] = $settings

            Write-ConfigRoot -Path $path -Root $root
            $settings
        }
    } catch {
        throw "Could not save the settings: $($_.Exception.Message)"
    }
}
