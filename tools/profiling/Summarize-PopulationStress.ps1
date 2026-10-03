param([Parameter(Mandatory)][string]$Session)
$ErrorActionPreference = 'Stop'
$meta = Get-Content -Raw "$Session/session.json" | ConvertFrom-Json
if ($meta.status -ne 'stress-completed') { throw 'Session did not complete' }
$frames = @(Import-Csv "$Session/appdata/stress-frames.csv")
$measured = @($frames | Where-Object stage -eq '3')
$times = @($measured | ForEach-Object { [double]$_.frame_ms } | Sort-Object)
if ($times.Count -lt 2 -or $times[0] -le 0) { throw 'Missing or invalid measured frame durations' }
$span = ([double]$measured[-1].game_ms - [double]$measured[0].game_ms) / 1000
if ($span -lt 29) { throw 'Measurement interval shorter than expected' }
$log = [IO.File]::ReadAllText((Get-ChildItem "$Session/appdata/logs" -Filter '*.log')[0].FullName)
$population = @([regex]::Matches($log,'\[stress population\] game_ms=(\d+) stage=3 requested=(\d+) retained=(\d+) living=(\d+) online=(\d+)') | ForEach-Object {
    [pscustomobject]@{retained=[int]$_.Groups[3].Value;living=[int]$_.Groups[4].Value;online=[int]$_.Groups[5].Value}
})
if (!$population.Count) { throw 'No measured population evidence' }
$spawn = [regex]::Match($log,'spawn_complete requested=\d+ created=\d+ spawn_ms=([\d.]+)')
$warmup = @($frames | Where-Object stage -eq '2' | ForEach-Object { [double]$_.frame_ms })
$metrics = @([regex]::Matches($log,'\[ALife metrics\] game_ms=(\d+) level=\d+ whole_map=1 online=\d+ offline=\d+ living_online=(\d+) living_offline=\d+ spawns=\d+ removals=\d+ updates=(\d+) switch_ms=([\d.]+) scheduled_ms=([\d.]+)') | ForEach-Object {
    [pscustomobject]@{time=[int]$_.Groups[1].Value;living=[int]$_.Groups[2].Value;updates=[int]$_.Groups[3].Value;switchMs=[double]$_.Groups[4].Value;scheduledMs=[double]$_.Groups[5].Value}
} | Where-Object { $_.time -ge ([int]$measured[0].game_ms + 1000) -and $_.time -le [int]$measured[-1].game_ms })
if (!$metrics.Count) { throw 'No A-Life metrics inside measurement window' }
$updates = ($metrics.updates | Measure-Object -Sum).Sum
$result = [ordered]@{
    session=$meta.session; extraRequested=$meta.requestedExtraStalkers; engineSha256=$meta.engineSha256
    frames=$times.Count; seconds=$span; meanMs=($times | Measure-Object -Average).Average
    medianMs=$times[[int][math]::Ceiling($times.Count*0.5)-1]
    p95Ms=$times[[int][math]::Ceiling($times.Count*0.95)-1]
    p99Ms=$times[[int][math]::Ceiling($times.Count*0.99)-1]; maxMs=$times[-1]
    over33ms=@($times | Where-Object { $_ -gt 33.3333 }).Count
    over50ms=@($times | Where-Object { $_ -gt 50 }).Count
    spawnCallMs=[double]$spawn.Groups[1].Value; activationWarmupMaxMs=($warmup | Measure-Object -Maximum).Maximum
    spawnedLivingMin=($population.living | Measure-Object -Minimum).Minimum
    spawnedLivingMax=($population.living | Measure-Object -Maximum).Maximum
    spawnedOnlineMin=($population.online | Measure-Object -Minimum).Minimum
    spawnedOnlineMax=($population.online | Measure-Object -Maximum).Maximum
    spawnedRetainedMin=($population.retained | Measure-Object -Minimum).Minimum
    totalLivingOnlineMean=($metrics.living | Measure-Object -Average).Average
    alifeSwitchMsPerUpdate=($metrics.switchMs | Measure-Object -Sum).Sum / $updates
    alifeOfflineScheduledMsPerUpdate=($metrics.scheduledMs | Measure-Object -Sum).Sum / $updates
}
$result | ConvertTo-Json | Set-Content "$Session/stress-summary.json" -Encoding utf8
[pscustomobject]$result
