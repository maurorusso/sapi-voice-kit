# /sapi-voice-kit:test - speaks one fixed sentence that exercises every
# text-cleanup rule and the pronunciation dictionary, through the same
# pipeline natural mode uses. Run it after changing anything in lib/ and
# listen: audio cannot be checked by an assertion.

. "$PSScriptRoot\common.ps1"

$context = New-ScriptContext -LogFile 'log-say-test.txt'

$testText = Get-TestSentence

$cleaned = Get-CleanedText -Text $testText
Write-Output "Texto original:`n$testText`n"
Write-Output "Texto limpio (lo que se procesa para hablar):`n$cleaned`n"

try {
    Invoke-SpeechSynthesis -Text $cleaned -Config $context.Config -Log $context.Log
    Write-Output "Listo - si no escuchaste nada, revisá que el volumen esté prendido y que haya una voz instalada (/sapi-voice-kit:voice)."
} catch {
    Write-Output "Error al hablar: $($_.Exception.Message)"
}
