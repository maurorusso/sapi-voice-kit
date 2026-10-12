# The speaking rate shared by both engines: -10 (slowest) .. 10 (fastest),
# the scale SAPI5 itself uses.

$script:SpeechRateMin = -10
$script:SpeechRateMax = 10

# The config's rate clamped to the range the engines accept. A bad value in
# config.json must never throw and silence the plugin.
function ConvertTo-SafeRate {
    param($Value)
    $rate = 0
    if (-not [int]::TryParse("$Value", [ref]$rate)) { return 0 }
    return [math]::Max($script:SpeechRateMin, [math]::Min($script:SpeechRateMax, $rate))
}
