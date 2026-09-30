# Unit tests for scripts/common.ps1 - dev-only tooling, never shipped with
# the plugin (same principle as Pester itself: this project's zero
# runtime-dependency promise is about what the installed plugin needs, not
# what's used to develop it). Run with:
#   powershell -NoProfile -Command "Invoke-Pester tests/common.Tests.ps1"
#
# Uses Pester 3.4 syntax on purpose - that's what's actually bundled with
# Windows PowerShell 5.1 on a stock machine (confirmed via
# `Get-Module -ListAvailable Pester`), so running these tests never requires
# installing anything extra, matching this project's own "no installers"
# stance for its own tooling too.
#
# What's NOT covered here, deliberately: whether audio actually sounds
# right. That's inherently not something an assertion can check - it's
# covered by /sapi-voice-kit:test (say-test.ps1), a listen-and-confirm-by-ear
# script, and stays that way. Everything below is pure text-in/text-out or
# file-in/file-out logic with no synthesis involved.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $here
. "$repoRoot\scripts\common.ps1"

Describe "ConvertTo-SpokenDotfiles" {
    It "converts a bare leading-dot file mentioned in prose" {
        (ConvertTo-SpokenDotfiles -Text "abrí .env por favor") | Should Be "abrí punto env por favor"
    }
    It "converts a dotfile with a compound extension inside backticks" {
        (ConvertTo-SpokenDotfiles -Text "mirá ``.mcp.json``") | Should Be "mirá ``punto mcp punto json``"
    }
    It "leaves a normal sentence with no dotfile untouched" {
        (ConvertTo-SpokenDotfiles -Text "esto no tiene nada raro") | Should Be "esto no tiene nada raro"
    }
}

Describe "ConvertTo-SpokenFileNames" {
    It "collapses a relative path with a known extension to just the file name" {
        (ConvertTo-SpokenFileNames -Text "mirá scripts/common.ps1 ahora") | Should Be "mirá common punto ps1 ahora"
    }
    It "collapses a Windows absolute path with a known extension" {
        (ConvertTo-SpokenFileNames -Text "abrí C:\Desarrollos\IA\proyectos\sapi-voice-kit\README.md") | Should Be "abrí README punto md"
    }
    It "leaves an unrecognized extension untouched" {
        (ConvertTo-SpokenFileNames -Text "el archivo foo.xyz") | Should Be "el archivo foo.xyz"
    }
}

Describe "ConvertTo-SpokenPaths" {
    It "collapses a bare drive-absolute folder path to its last segment" {
        (ConvertTo-SpokenPaths -Text "andá a C:\Desarrollos\IA") | Should Be "andá a IA"
    }
    It "leaves prose with no drive letter untouched" {
        (ConvertTo-SpokenPaths -Text "esto es una oración normal") | Should Be "esto es una oración normal"
    }
}

Describe "ConvertTo-SpokenUrls" {
    It "replaces a bare https URL with the site's brand name" {
        (ConvertTo-SpokenUrls -Text "mirá https://github.com/maurorusso/sapi-voice-kit") | Should Be "mirá el link de github"
    }
    It "strips a www prefix before picking the brand name" {
        (ConvertTo-SpokenUrls -Text "https://www.example.com/algo") | Should Be "el link de example"
    }
    It "leaves text with no URL untouched" {
        (ConvertTo-SpokenUrls -Text "no hay ningún link acá") | Should Be "no hay ningún link acá"
    }
}

Describe "ConvertTo-SpokenAbbreviations" {
    It "expands a sentence-final etc. and keeps the sentence boundary" {
        (ConvertTo-SpokenAbbreviations -Text "gatos, perros, etc. Después seguimos.") | Should Be "gatos, perros, etcétera. Después seguimos."
    }
    It "expands etc even without its period (the pattern's dot is optional) and adds no stray period" {
        (ConvertTo-SpokenAbbreviations -Text "cosas, etc, que uses") | Should Be "cosas, etcétera, que uses"
    }
    It "expands Dr. before a name without inserting a false sentence break" {
        (ConvertTo-SpokenAbbreviations -Text "hablé con el Dr. García ayer") | Should Be "hablé con el doctor García ayer"
    }
    It "does not expand VS as a bare product-name fragment (no period)" {
        (ConvertTo-SpokenAbbreviations -Text "lo abrí en VS Code") | Should Be "lo abrí en VS Code"
    }
}

Describe "Add-ImplicitLineEndPeriods" {
    It "adds a period to a line break with no existing punctuation" {
        $result = Add-ImplicitLineEndPeriods -Text "primera línea`nsegunda línea"
        $result | Should Be "primera línea.`nsegunda línea"
    }
    It "does not add a period to a line already ending in real punctuation" {
        $result = Add-ImplicitLineEndPeriods -Text "una pregunta?`notra línea"
        $result | Should Be "una pregunta?`notra línea"
    }
}

Describe "Get-CleanedText (full pipeline)" {
    It "strips a markdown link down to its label" {
        (Get-CleanedText -Text "mirá [la doc](https://example.com)") | Should Be "mirá la doc"
    }
    It "strips a bullet marker from the start of a line" {
        (Get-CleanedText -Text "- primer punto") | Should Be "primer punto"
    }
    It "collapses a code block to a short spoken placeholder" {
        (Get-CleanedText -Text 'antes ```code aca``` despues') | Should Be "antes  code block omitted.  despues"
    }
}

Describe "Namespaced config (Get-VoiceConfig / Save-VoiceConfig)" {
    $testUserProfile = Join-Path ([System.IO.Path]::GetTempPath()) ("sapi-voice-kit-test-" + [Guid]::NewGuid().ToString("N"))
    $originalUserProfile = $env:USERPROFILE
    $fakePluginData = Join-Path $testUserProfile "fake-install"

    New-Item -ItemType Directory -Path $fakePluginData -Force | Out-Null
    $env:USERPROFILE = $testUserProfile
    # Resolve-SharedDataDir memoizes per PROCESS (real-world processes never
    # change $env:USERPROFILE mid-run, so that's safe there) - this test
    # file swaps it between Describe blocks to isolate each one in its own
    # fake home directory, so the memoization must be reset here too, or a
    # later block would silently reuse the first block's resolved path.
    $script:SharedDataDirCleanupDone = $false

    It "saves a value under the local namespace by default" {
        Save-VoiceConfig -PluginData $fakePluginData -Changes @{ mode = 'active' } | Out-Null
        $config = Get-VoiceConfig -PluginData $fakePluginData
        $config.mode | Should Be 'active'
    }

    It "keeps local and cowork independent - saving to cowork doesn't touch local" {
        Save-VoiceConfig -PluginData $fakePluginData -Namespace 'local' -Changes @{ voiceName = 'Microsoft Laura' } | Out-Null
        Save-VoiceConfig -PluginData $fakePluginData -Namespace 'cowork' -Changes @{ voiceName = 'Microsoft Pablo' } | Out-Null

        $local = Get-VoiceConfig -PluginData $fakePluginData -Namespace 'local'
        $cowork = Get-VoiceConfig -PluginData $fakePluginData -Namespace 'cowork'

        $local.voiceName | Should Be 'Microsoft Laura'
        $cowork.voiceName | Should Be 'Microsoft Pablo'
    }

    It "reading an unset namespace returns null instead of throwing" {
        $missing = Get-VoiceConfig -PluginData $fakePluginData -Namespace 'nunca-configurado'
        $missing | Should Be $null
    }

    $env:USERPROFILE = $originalUserProfile
    Remove-Item -Path $testUserProfile -Recurse -Force -ErrorAction SilentlyContinue
}

Describe "Resolve-SharedDataDir migration and cleanup safety" {
    $testUserProfile = Join-Path ([System.IO.Path]::GetTempPath()) ("sapi-voice-kit-test-" + [Guid]::NewGuid().ToString("N"))
    $originalUserProfile = $env:USERPROFILE
    $oldInstallDir = Join-Path $testUserProfile "old-install"
    New-Item -ItemType Directory -Path $oldInstallDir -Force | Out-Null

    # Seed the old per-install folder with a real plugin file AND a file
    # that is explicitly NOT this plugin's - this is the direct, automated
    # proof for "asegurame que no vas a eliminar nada que no sea nuestro":
    # if the cleanup logic is ever widened by accident to delete more than
    # its known filename list, this test catches it.
    '{"mode": "active", "voiceName": "Microsoft Laura"}' | Set-Content -Path (Join-Path $oldInstallDir "config.json") -Encoding UTF8
    "esto no es del plugin, no se tiene que tocar" | Set-Content -Path (Join-Path $oldInstallDir "not-ours.txt") -Encoding UTF8

    $env:USERPROFILE = $testUserProfile
    $script:SharedDataDirCleanupDone = $false

    It "migrates the old flat config into the local namespace" {
        $dir = Resolve-SharedDataDir -PluginData $oldInstallDir
        $config = Get-VoiceConfig -PluginData $oldInstallDir -Namespace 'local'
        $config.voiceName | Should Be 'Microsoft Laura'
    }

    It "deletes the old install's own config.json once migrated" {
        (Test-Path (Join-Path $oldInstallDir "config.json")) | Should Be $false
    }

    It "never touches a file that isn't this plugin's own" {
        (Test-Path (Join-Path $oldInstallDir "not-ours.txt")) | Should Be $true
        (Get-Content -Path (Join-Path $oldInstallDir "not-ours.txt") -Raw) | Should Be "esto no es del plugin, no se tiene que tocar`r`n"
    }

    It "does not delete a second install's un-migrated config.json (data-loss regression)" {
        # Reproduces the exact bug found live while building this: the
        # shared dir already exists (from the migration above), so a
        # SECOND, different install's own config.json must survive
        # untouched - it was never copied anywhere, so deleting it would be
        # silent data loss, not cleanup.
        $secondInstallDir = Join-Path $testUserProfile "second-install"
        New-Item -ItemType Directory -Path $secondInstallDir -Force | Out-Null
        '{"mode": "natural", "voiceName": "Microsoft Helena"}' | Set-Content -Path (Join-Path $secondInstallDir "config.json") -Encoding UTF8

        # Resolve-SharedDataDir memoizes per process (see the comment on
        # $script:SharedDataDirCleanupDone in common.ps1) - real processes
        # never call it with two different $PluginData values (each install
        # is its own process with one fixed value for its whole life), so
        # this reset simulates the second install being a genuinely
        # separate process, matching the real scenario this test reproduces.
        $script:SharedDataDirCleanupDone = $false
        Resolve-SharedDataDir -PluginData $secondInstallDir | Out-Null

        (Test-Path (Join-Path $secondInstallDir "config.json")) | Should Be $true
        # And its settings were correctly NOT folded into the shared file
        # either - it wasn't migrated, so it must not silently overwrite
        # what the first install already migrated.
        $local = Get-VoiceConfig -PluginData $secondInstallDir -Namespace 'local'
        $local.voiceName | Should Be 'Microsoft Laura'
    }

    $env:USERPROFILE = $originalUserProfile
    Remove-Item -Path $testUserProfile -Recurse -Force -ErrorAction SilentlyContinue
}

Describe "Invoke-WithConfigLock under real concurrent processes" {
    # Every other test in this file simulates "a different process" by
    # resetting $script:SharedDataDirCleanupDone in the SAME PowerShell
    # process - useful for the decision logic, but it never actually
    # exercises Invoke-WithConfigLock's mutex under genuine parallel
    # execution (a reviewer flagged this gap directly). This test spins up
    # real, separate powershell.exe child processes via Start-Job (Windows
    # PowerShell's classic job type - not a thread, an actual child
    # process) that all race to write to the same config.json at once, and
    # checks that every single one of their writes survived. Without the
    # lock, this reliably loses writes (confirmed by temporarily commenting
    # out the Invoke-WithConfigLock call while developing this test - most
    # runs lost at least one of the ten keys).
    $testUserProfile = Join-Path ([System.IO.Path]::GetTempPath()) ("sapi-voice-kit-test-" + [Guid]::NewGuid().ToString("N"))
    $originalUserProfile = $env:USERPROFILE
    $fakePluginData = Join-Path $testUserProfile "fake-install"
    New-Item -ItemType Directory -Path $fakePluginData -Force | Out-Null
    # Deliberately NOT overriding $env:USERPROFILE in this (parent) process -
    # Start-Job's own job-persistence infrastructure needs a real, valid
    # user profile to function at all (confirmed live: overriding it here
    # made Start-Job itself fail with "The Persistence Path does not
    # exist", before any of this test's own code ran). Each background job
    # sets the override for ITSELF instead, inside its own process - which
    # is exactly the real-world shape anyway, since every real process has
    # one fixed $env:USERPROFILE for its whole life.

    It "loses no writes when 10 real separate processes save to the same namespace concurrently" {
        $jobCount = 10
        $jobs = 1..$jobCount | ForEach-Object {
            Start-Job -ScriptBlock {
                param($commonPath, $pluginData, $i, $fakeHome)
                $env:USERPROFILE = $fakeHome
                . $commonPath
                Save-VoiceConfig -PluginData $pluginData -Namespace 'local' -Changes @{ "key$i" = $true } | Out-Null
            } -ArgumentList "$repoRoot\scripts\common.ps1", $fakePluginData, $_, $testUserProfile
        }

        $jobs | Wait-Job -Timeout 60 | Out-Null
        $jobs | Receive-Job | Out-Null
        $jobs | Remove-Job -Force

        $env:USERPROFILE = $testUserProfile
        try {
            $config = Get-VoiceConfig -PluginData $fakePluginData -Namespace 'local'
        } finally {
            $env:USERPROFILE = $originalUserProfile
        }
        $missingKeys = 1..$jobCount | Where-Object { -not $config.ContainsKey("key$_") }
        $missingKeys.Count | Should Be 0
    }

    Remove-Item -Path $testUserProfile -Recurse -Force -ErrorAction SilentlyContinue
}
