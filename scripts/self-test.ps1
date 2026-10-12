# /sapi-voice-kit:selftest - runs every reading mode for real, out loud, and
# checks with the output-level meter that sound came out when it should and
# stayed silent when it should. Takes about 3 minutes and speaks the whole time.
#
# It uses a throwaway home folder, so the real settings are not touched, and a
# voice other than the one in use (-Voice to choose), so it is clear which
# speech is the test and which is the plugin talking.
#
#   -PlanOnly  print exactly what will be heard, in order, and stop: no sound
#   -NoWait    start at once instead of after a short countdown

param(
    [string]$Voice,
    [switch]$PlanOnly,
    [switch]$NoWait
)

. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\lib\audio-meter.ps1"

$pluginRoot = Split-Path -Parent $PSScriptRoot
$utf8 = New-Object System.Text.UTF8Encoding($false)

# --- which voice speaks the test --------------------------------------------
$voices = @(Get-InstalledVoices)
$inUse = Resolve-SpeechTarget -Config (Get-VoiceConfig) -Voices $voices
if ($Voice) {
    $testVoice = $voices | Where-Object { $_.Name -eq $Voice } | Select-Object -First 1
    if (-not $testVoice) { Write-Output "No hay una voz instalada llamada '$Voice'. Mirá /sapi-voice-kit:voice."; exit 1 }
} else {
    $language = if ($inUse.Language) { $inUse.Language } else { (Get-Culture).Name }
    $prefix = $language.Split('-')[0]
    $testVoice = $voices | Where-Object { $_.Name -ne $inUse.Name -and $_.Language.Split('-')[0] -eq $prefix } | Select-Object -First 1
    if (-not $testVoice) { $testVoice = $inUse }
}
$testVoiceName = $testVoice.Name

# --- the steps ---------------------------------------------------------------
# Expect: 'sound' (must be heard) or 'silent' (must not). Hear: what is said.
function New-HookEvent([string]$Message) { return (@{ last_assistant_message = $Message } | ConvertTo-Json -Compress) }
function New-McpCall([int]$Id, [string]$Name, [string]$Arguments = '{}') {
    return '{"jsonrpc":"2.0","id":' + $Id + ',"method":"tools/call","params":{"name":"' + $Name + '","arguments":' + $Arguments + '}}'
}
$mcpHello = '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{}}'

$steps = @(
    @{ Label = 'say-test (la oración larga de prueba, ~30 s)'; Expect = 'sound'; Hear = (Get-CleanedText -Text (Get-TestSentence))
       Script = 'say-test.ps1' }
    @{ Label = 'modo natural'; Expect = 'sound'; Hear = (Get-CleanedText -Text "# Prueba natural`n`nEsto es **modo natural**: lee [este link](https://github.com/x) y dice git y commit.")
       Set = @{ mode = 'natural' }; Script = 'speak.ps1'
       Stdin = (New-HookEvent "# Prueba natural`n`nEsto es **modo natural**: lee [este link](https://github.com/x) y dice git y commit.") }
    @{ Label = 'modo literal'; Expect = 'sound'; Hear = 'Esto es el modo literal, tal cual está escrito.'
       Set = @{ mode = 'literal' }; Script = 'speak.ps1'; Stdin = (New-HookEvent 'Esto es el modo literal, tal cual está escrito.') }
    @{ Label = 'modo resumen'; Expect = 'sound'; Hear = 'Un resumen corto que escribe Claude (no se puede saber el texto de antemano). Si Claude no puede resumir, lee entero: «Esta es una respuesta larga para resumir. Habla de cómo se reestructuró el código en módulos, se agregaron pruebas automáticas y se corrigieron errores de acentos en el servidor MCP.» Tarda ~25 s en empezar.'
       Set = @{ mode = 'summary' }; Script = 'speak.ps1'
       Stdin = (New-HookEvent 'Esta es una respuesta larga para resumir. Habla de cómo se reestructuró el código en módulos, se agregaron pruebas automáticas y se corrigieron errores de acentos en el servidor MCP.') }
    @{ Label = 'modo activo: el hook queda callado'; Expect = 'silent'; Hear = 'NADA. Si oís «Esto no debe oirse: el modo activo deja callado al hook», falló.'
       Set = @{ mode = 'active' }; Script = 'speak.ps1'; Stdin = (New-HookEvent 'Esto no debe oirse: el modo activo deja callado al hook.') }
    @{ Label = 'modo activo: say.ps1'; Expect = 'sound'; Hear = 'Prueba del modo activo. Mirá el archivo common punto ps1.'
       Script = 'say.ps1'; Stdin = 'Prueba del modo activo. Mirá el archivo common punto ps1.' }
    @{ Label = 'segunda frase seguida (se saltea)'; Expect = 'silent'; Hear = 'NADA. Si oís «Esto no debe oirse: es la segunda seguida», falló.'
       Script = 'say.ps1'; Stdin = 'Esto no debe oirse: es la segunda seguida.' }
    @{ Label = 'con mute, el hook queda callado'; Expect = 'silent'; Hear = 'NADA. Si oís «Esto no debe oirse: esta silenciado», falló.'
       Set = @{ mode = 'natural'; muted = $true }; Script = 'speak.ps1'; Stdin = (New-HookEvent 'Esto no debe oirse: esta silenciado.') }
    @{ Label = 'con mute, pero forzado'; Expect = 'sound'; Hear = 'Leeme eso, forzado aunque esté silenciado.'
       Script = 'say.ps1'; Args = @('-Force'); Stdin = 'Leeme eso, forzado aunque esté silenciado.' }
)

$node = Get-Command node -ErrorAction SilentlyContinue
if ($node) {
    $steps += @(
        @{ Label = 'Cowork: modo activo + read_aloud'; Expect = 'sound'; Hear = 'Hola desde Cowork. ¿Confirmás, García?'; Mcp = $true
           Set = @{ muted = $false }; SetCowork = $true
           Calls = @((New-McpCall 1 'set_mode' '{"mode":"active"}'), (New-McpCall 2 'read_aloud' '{"text":"Hola desde Cowork. ¿Confirmás, García?"}')) }
        @{ Label = 'Cowork: modo natural + read_aloud'; Expect = 'silent'; Hear = 'NADA. Si oís «Esto no debe oirse: Cowork no esta en modo activo», falló.'; Mcp = $true
           Calls = @((New-McpCall 1 'set_mode' '{"mode":"natural"}'), (New-McpCall 2 'read_aloud' '{"text":"Esto no debe oirse: Cowork no esta en modo activo."}')) }
        @{ Label = 'Cowork: read_aloud forzado'; Expect = 'sound'; Hear = 'Forzado desde Cowork, se oye igual.'; Mcp = $true
           Calls = @((New-McpCall 1 'read_aloud' '{"text":"Forzado desde Cowork, se oye igual.","force":true}')) }
    )
}

# --- plan --------------------------------------------------------------------
Write-Output "Voz de la prueba: $testVoiceName (el plugin está usando: $(if ($inUse.Name) { $inUse.Name } else { 'la predeterminada' }))"
Write-Output ''
Write-Output 'Lo que se va a oír, en orden (SUENA = debe oírse ese texto; SILENCIO = no debe oírse nada):'
$number = 0
foreach ($step in $steps) {
    $number++
    $kind = if ($step.Expect -eq 'sound') { 'SUENA  ' } else { 'SILENCIO' }
    Write-Output ('  {0,2}. {1} {2}' -f $number, $kind, $step.Label)
    Write-Output ('      {0}' -f $step.Hear)
}
if (-not $node) { Write-Output '  (Los pasos de Cowork se saltean: no hay Node.js.)' }
Write-Output ''
if ($PlanOnly) { exit 0 }
if (-not $NoWait) {
    Write-Output 'Empieza en 8 segundos. Ponete cerca de los parlantes...'
    Start-Sleep -Seconds 8
}

# --- run ---------------------------------------------------------------------
Initialize-AudioMeter
$realHome = $env:USERPROFILE
$env:USERPROFILE = Join-Path ([System.IO.Path]::GetTempPath()) ('sapi-voice-kit-selftest-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $env:USERPROFILE -Force | Out-Null
Remove-Item Env:\SAPI_VOICE_NAMESPACE -ErrorAction SilentlyContinue
foreach ($section in 'local', 'cowork') {
    Save-VoiceConfig -Namespace $section -Changes @{ voiceName = $testVoiceName; rate = 0; mode = 'natural' } | Out-Null
}

# Runs one child process, watching the output level until it exits.
function Invoke-Watched {
    param([string]$FileName, [string]$Arguments, [string]$Stdin)
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $FileName
    $info.Arguments = $Arguments
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = $utf8
    $info.StandardErrorEncoding = $utf8
    $process = [System.Diagnostics.Process]::Start($info)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if ($Stdin) {
        $bytes = $utf8.GetBytes($Stdin)
        $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    }
    # The underlying stream is closed, not the writer, which would add a byte-order mark.
    $process.StandardInput.BaseStream.Close()
    $peak = 0.0
    while (-not $process.HasExited) {
        $level = [OutputMeter]::Peak()
        if ($level -gt $peak) { $peak = $level }
        Start-Sleep -Milliseconds 20
    }
    $process.WaitForExit()
    return [pscustomobject]@{ Peak = $peak; Output = ($stdout.Result + $stderr.Result).Trim() }
}

$ambient = Get-AudioPeak -Milliseconds 1500
if ($ambient -gt 0.05) { Write-Output "Aviso: hay otro audio sonando ahora (nivel $([math]::Round($ambient, 2))); los pasos en silencio pueden dar falso FAIL. Pausalo y repetí si pasa." }
$silentLimit = [math]::Max(0.05, $ambient + 0.05)
$soundMinimum = 0.2

$failures = 0
$number = 0
try {
    foreach ($step in $steps) {
        $number++
        if ($step.Set) { Save-VoiceConfig -Namespace $(if ($step.SetCowork) { 'cowork' } else { 'local' }) -Changes $step.Set | Out-Null }

        if ($step.Mcp) {
            $lines = @($mcpHello) + $step.Calls
            $result = Invoke-Watched -FileName $node.Source -Arguments "`"$pluginRoot\mcp-server\server.js`"" -Stdin ($lines -join "`n")
        } else {
            $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\$($step.Script)`" $($step.Args -join ' ')"
            $result = Invoke-Watched -FileName 'powershell' -Arguments $arguments -Stdin $step.Stdin
        }

        $passed = if ($step.Expect -eq 'sound') { $result.Peak -ge $soundMinimum } else { $result.Peak -le $silentLimit }
        if (-not $passed) { $failures++ }
        $detail = ($result.Output -split "`n" | Where-Object { $_ } | Select-Object -Last 1)
        Write-Output ('{0} {1,2}. {2} (esperado: {3}, nivel {4:N2}) {5}' -f $(if ($passed) { 'PASS' } else { 'FAIL' }), $number, $step.Label, $step.Expect, $result.Peak, $detail)
        Start-Sleep -Milliseconds 800
    }
} finally {
    # The throwaway home goes away even if the run is interrupted.
    Remove-Item -Path $env:USERPROFILE -Recurse -Force -ErrorAction SilentlyContinue
    $env:USERPROFILE = $realHome
}

Write-Output ''
Write-Output "$($steps.Count) pasos, $failures fallaron."
Write-Output 'Esto confirma que sale (o no sale) sonido; que se entienda bien se juzga de oído.'
exit $(if ($failures -eq 0) { 0 } else { 1 })
