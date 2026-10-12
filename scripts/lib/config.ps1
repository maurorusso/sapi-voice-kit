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

$script:ConfigNamespaces = @('local', 'cowork')
$script:ConfigLockName = 'Local\SapiVoiceKitConfig'
$script:ConfigLockTimeoutMs = 5000

function Get-SharedDataDir {
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
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
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
    if (-not (Test-Path $Path)) { return $root }
    $text = [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding($false)))
    try {
        $parsed = $text | ConvertFrom-Json
    } catch {
        throw (New-Object System.FormatException("config.json is not valid JSON: $($_.Exception.Message)"))
    }
    foreach ($section in $parsed.psobject.Properties) {
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
        if (Test-Path $Path) {
            [System.IO.File]::Replace($temp, $Path, [NullString]::Value)
        } else {
            Move-Item -Path $temp -Destination $Path
        }
    } finally {
        if (Test-Path $temp) { Remove-Item -Path $temp -Force }
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
    if ($root.ContainsKey($Namespace)) { return $root[$Namespace] }
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

    $path = Join-Path (Initialize-SharedDataDir) 'config.json'
    return Invoke-WithNamedMutex -Name $script:ConfigLockName -TimeoutMs $script:ConfigLockTimeoutMs -Action {
        try {
            $root = Read-ConfigRoot -Path $path
        } catch [System.FormatException] {
            Move-Item -Path $path -Destination "$path.bad" -Force
            $root = @{}
        }

        $settings = if ($root.ContainsKey($Namespace)) { $root[$Namespace] } else { @{} }
        foreach ($key in $Changes.Keys) { $settings[$key] = $Changes[$key] }
        foreach ($key in $Remove) { $settings.Remove($key) }
        $root[$Namespace] = $settings

        Write-ConfigRoot -Path $path -Root $root
        $settings
    }
}
