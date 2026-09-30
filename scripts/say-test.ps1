# /sapi-voice-kit:test - speaks one fixed sentence that deliberately
# exercises every text-cleanup function this plugin has (dictionary terms,
# monosyllable stress, castellanized words, dotfiles - bare and in
# backticks -, full paths, URLs, markdown links, abbreviations - including
# the two that previously broke on real names/product names -, a question,
# a line break with no trailing period, and a bullet list), through the
# exact same Get-CleanedText -> Invoke-SpeechSynthesis pipeline natural mode
# uses.
#
# Added after a code-review pass found several of these functions had real
# bugs that only surfaced with specific inputs (an abbreviation eating a
# sentence's only period, a dotfile inside backticks left unconverted, "VS
# Code" becoming "versus Code") - each one was caught by hand-writing a
# throwaway test script, listening, then deleting it. This is that throwaway
# script made permanent: run `/sapi-voice-kit:test` after touching anything
# in common.ps1's text-cleanup pipeline or $script:TechPronunciations,
# instead of writing a new one-off script each time.

param(
    [Parameter(Mandatory)][string]$PluginData,
    [ValidateSet('local', 'cowork')]
    [string]$Namespace = 'local'
)

. "$PSScriptRoot\common.ps1"

$config = Get-VoiceConfig -PluginData $PluginData -Namespace $Namespace
$debugOn = $config -and $config.debug -eq $true
$Log = Get-Logger -PluginData $(if ($debugOn) { $PluginData } else { $null }) -FileName "log-say-test.txt"

# Every line below targets a specific function or a specific bug that was
# found and fixed live - see the comment on each cleanup function in
# common.ps1 for the full story behind why each one is here.
$script:TestText = @'
Che, revisá `.mcp.json`, el .env, y también scripts/common.ps1 — el repo está en https://github.com/maurorusso/sapi-voice-kit, o mirá [la documentación](https://github.com/maurorusso/sapi-voice-kit#readme).
Usé git para el commit y quedó un bug en la skill del prompt, etc. Probé con VS Code y con el Dr. García, todo bien.
¿Confirmás que ya lo probamos?
- Primer punto de la lista
- Segundo punto sin punto final
Por último, node y javascript corren en localhost.
'@

Write-Output "Texto original:`n$script:TestText`n"
$cleaned = Get-CleanedText -Text $script:TestText
Write-Output "Texto limpio (lo que se procesa para hablar):`n$cleaned`n"

try {
    & $Log "starting test speech ($($cleaned.Length) characters)"
    Invoke-SpeechSynthesis -Text $cleaned -Config $config -UsePronunciation $true -Log $Log
    Write-Output "Listo - si no escuchaste nada, revisá que el volumen esté prendido y que haya una voz instalada (/sapi-voice-kit:voice)."
} catch {
    & $Log "EXCEPTION: $($_.Exception.GetType().Name): $($_.Exception.Message)"
    Write-Output "Error al hablar: $($_.Exception.Message)"
}
