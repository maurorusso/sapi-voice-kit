# Text the model writes only to be heard (summary mode, active mode's
# per-turn instruction, read-last). It never appears on screen, so it can be
# worded purely for the ear.

# Shared by Get-AiSummary below and prompt-active-mode.ps1. skills/read-last
# and skills/cowork keep a copy in prose (a skill is static markdown and cannot
# interpolate this); tests/repo.test.js fails if a copy loses one of the three rules (file names, URLs, paths).
$script:SpokenTextGuidance = 'If you mention a file name, say the word for a period (e.g. "punto" in Spanish, "dot" in English) instead of writing a literal "." character, since a raw dot right before a file extension reads oddly aloud (for example write "common punto pe ese uno", not "common.ps1"). If you would mention a URL or link, do not write it out - refer to it by its site name instead (e.g. "el link de GitHub") so two different links in the same response are still told apart, and let the reader look at the screen for the actual address, since a raw URL read aloud (the "https://" part especially) sounds wrong. Same idea for a full file path (e.g. "C:\Users\...\common.ps1" or "scripts/common.ps1") - just say the file name, not every folder in between.'

# How long the summary call may take before the full text is read instead.
$script:SummaryTimeoutMs = 90000

# "summary" mode: asks Claude for a short spoken-style summary of $Text with a
# separate `claude -p` call (about 20 s, which is why the mode is opt-in).
# --safe-mode keeps that call from loading this plugin's own hooks, --tools ""
# leaves it with no tools (it only has to write a summary, so text inside the
# response can never make it read files), --no-session-persistence keeps it from saving a transcript of the response in
# the user's Claude folder, and the prompt goes through stdin because a long
# response would exceed the Windows command-line limit as an argument. Returns $null on any failure so the caller
# can read the full text instead.
function Get-AiSummary {
    param([Parameter(Mandatory)][string]$Text)

    $prompt = "Summarize the following text in 2-4 natural spoken sentences that capture the main points, in the same language as the text. This summary will ONLY ever be spoken aloud by a text-to-speech engine, never shown on screen - write it accordingly. $($script:SpokenTextGuidance) Avoid markdown, raw symbols, and abbreviations that wouldn't make sense read aloud. Output ONLY the summary itself - no preamble, no options, no alternate phrasings, no quotation marks around it, nothing else.`n`n---`n`n$Text"

    # claude runs as a child process with a time limit: a call that hangs (no network) must not
    # hold the end of the turn until the hook is killed with nothing read at all. The prompt goes
    # in and the answer comes out as UTF-8 bytes, whatever the console's codepage.
    $claude = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $claude) { return $null }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $process = $null
    try {
        $info = New-Object System.Diagnostics.ProcessStartInfo
        $info.FileName = $claude.Source
        $info.Arguments = '-p --safe-mode --tools "" --no-session-persistence --model haiku'
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.RedirectStandardInput = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $info.StandardOutputEncoding = $utf8
        $process = [System.Diagnostics.Process]::Start($info)
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $null = $process.StandardError.ReadToEndAsync()
        $bytes = $utf8.GetBytes($prompt)
        $deadline = [DateTime]::UtcNow.AddMilliseconds($script:SummaryTimeoutMs)
        $write = $process.StandardInput.BaseStream.WriteAsync($bytes, 0, $bytes.Length)
        $sent = $write.Wait($script:SummaryTimeoutMs)
        if ($sent) { $process.StandardInput.BaseStream.Close() }
        $left = [math]::Max(0, [int]($deadline - [DateTime]::UtcNow).TotalMilliseconds)
        if (-not $sent -or -not $process.WaitForExit($left)) {
            & taskkill.exe /PID $process.Id /T /F *> $null
            return $null
        }
        if ($process.ExitCode -ne 0) { return $null }
        # A grandchild that outlives claude can keep the pipe open: the read has the same deadline.
        $left = [math]::Max(0, [int]($deadline - [DateTime]::UtcNow).TotalMilliseconds)
        if (-not $stdout.Wait($left)) { return $null }
        $summary = $stdout.Result.Trim()
        if ($summary) { return $summary }
        return $null
    } catch {
        return $null
    } finally {
        if ($process) { $process.Dispose() }
    }
}
