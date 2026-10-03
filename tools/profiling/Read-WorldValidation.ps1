param([Parameter(Mandatory)][string]$Session)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/ValidationLog.ps1"
$logs = @(Get-ChildItem "$Session/appdata/logs" -Filter '*.log')
if ($logs.Count -ne 1) { throw 'Expected exactly one engine log in a private session' }
$snapshots = @(Get-ValidationSnapshots -Text ([IO.File]::ReadAllText($logs[0].FullName)))
if ($snapshots.Count -eq 0) { throw 'No complete world snapshots found' }
$summary = foreach ($s in $snapshots) {
    $dupes = @($s.entities | Group-Object id | Where-Object Count -gt 1)
    $offmap = @($s.entities | Where-Object { [int]$_.online -eq 1 -and [int]$_.level -ne $s.level })
    [pscustomobject]@{
        stage=$s.stage; game_ms=$s.game_ms; level=$s.level; creatures=$s.entities.Count
        living=@($s.entities | Where-Object { [double]$_.health -gt 0 }).Count
        online=@($s.entities | Where-Object { $_.online -eq '1' }).Count
        duplicateIds=@($dupes | ForEach-Object Name); onlineOtherMapIds=@($offmap | ForEach-Object id)
    }
}
ConvertTo-Json -InputObject @($snapshots) -Depth 6 | Set-Content (Join-Path $Session 'world-snapshots.json') -Encoding utf8
ConvertTo-Json -InputObject @($summary) -Depth 5 | Set-Content (Join-Path $Session 'world-summary.json') -Encoding utf8
$summary | Format-Table stage,game_ms,level,creatures,living,online,@{n='duplicates';e={$_.duplicateIds.Count}},@{n='offmapOnline';e={$_.onlineOtherMapIds.Count}} -AutoSize
