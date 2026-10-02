param(
    [Parameter(Mandatory)][string]$Prefix,
    [Parameter(Mandatory)][double]$StartSeconds,
    [Parameter(Mandatory)][double]$EndSeconds
)
$ErrorActionPreference = 'Stop'
if ($EndSeconds -le $StartSeconds) { throw 'EndSeconds must exceed StartSeconds.' }
function Measure-Durations($Values) {
    [double[]]$sorted = @($Values | Sort-Object)
    if (!$sorted.Count) { return $null }
    $sum = ($sorted | Measure-Object -Sum).Sum
    [ordered]@{
        count = $sorted.Count; totalMs = $sum; meanMs = $sum / $sorted.Count
        medianMs = $sorted[[math]::Max(0, [math]::Ceiling($sorted.Count * .5) - 1)]
        p95Ms = $sorted[[math]::Max(0, [math]::Ceiling($sorted.Count * .95) - 1)]
        p99Ms = $sorted[[math]::Max(0, [math]::Ceiling($sorted.Count * .99) - 1)]
        maxMs = $sorted[-1]
    }
}
$startNs = $StartSeconds * 1e9
$endNs = $EndSeconds * 1e9
$frames = @(Import-Csv "$Prefix-frames.tsv" -Delimiter "`t" | Where-Object {
    [int]$_.index -ge 2 -and [double]$_.duration_ns -gt 0 -and [double]$_.start_ns -ge $startNs -and
    ([double]$_.start_ns + [double]$_.duration_ns) -le $endNs
})
if (!$frames.Count) { throw 'No complete frames in the requested interval.' }
$frameDurations = @($frames | ForEach-Object { [double]$_.duration_ns / 1e6 })
$zones = @(Import-Csv "$Prefix-zones.tsv" -Delimiter "`t" | Where-Object {
    [double]$_.duration_ns -ge 0 -and [double]$_.start_ns -ge $startNs -and
    ([double]$_.start_ns + [double]$_.duration_ns) -le $endNs
})
$result = [ordered]@{
    startSeconds = $StartSeconds; endSeconds = $EndSeconds
    selection = 'Complete events contained in interval; first two Tracy initialization frame markers excluded. May include in-game UI or pauses; this is not an automatic gameplay classifier.'
    percentileMethod = 'nearest rank'
    frames = Measure-Durations $frameDurations
    frameHistogram = [ordered]@{
        upTo8_33ms = @($frameDurations | Where-Object {$_ -le 8.333333}).Count
        over8_33To16_67ms = @($frameDurations | Where-Object {$_ -gt 8.333333 -and $_ -le 16.666667}).Count
        over16_67To33_33ms = @($frameDurations | Where-Object {$_ -gt 16.666667 -and $_ -le 33.333333}).Count
        over33_33To50ms = @($frameDurations | Where-Object {$_ -gt 33.333333 -and $_ -le 50}).Count
        over50ms = @($frameDurations | Where-Object {$_ -gt 50}).Count
    }
    zonesInclusive = @($zones | Group-Object name | ForEach-Object {
        [ordered]@{ name = $_.Name; timing = Measure-Durations @($_.Group | ForEach-Object {[double]$_.duration_ns / 1e6}); threadSlots = @($_.Group.thread_slot | Sort-Object -Unique) }
    })
    caveat = 'Zone durations include child zones, profiler overhead and time descheduled. They are not exclusive CPU utilization, and nested or parallel totals must not be added.'
}
$result | ConvertTo-Json -Depth 8 | Set-Content "$Prefix-summary.json" -Encoding utf8
$result | ConvertTo-Json -Depth 8
