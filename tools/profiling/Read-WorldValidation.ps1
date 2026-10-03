param([Parameter(Mandatory)][string]$Session)
$ErrorActionPreference = 'Stop'
$snapshots = [Collections.Generic.List[object]]::new()
$current = $null
$stage = 'initial'
$log = Get-ChildItem "$Session/appdata/logs" -Filter '*.log' | Select-Object -First 1
foreach ($line in [IO.File]::ReadLines($log.FullName)) {
    if ($line -match '\[ALife validation\] command=(.+) allowed=1') { $stage = $Matches[1] }
    if ($line -match '\[ALife world begin\] game_ms=(\d+) level=(\d+)') {
        $current = [ordered]@{ stage=$stage; game_ms=[int]$Matches[1]; level=[int]$Matches[2]; entities=[Collections.Generic.List[object]]::new() }
    } elseif ($line -match '\[ALife world\] (.+)' -and $null -ne $current) {
        $entity = [ordered]@{}
        foreach ($field in $Matches[1].Split(' ')) {
            $pair = $field.Split('=',2)
            $entity[$pair[0]] = $pair[1]
        }
        $current.entities.Add([pscustomobject]$entity)
    } elseif ($line -match '\[ALife world end\]' -and $null -ne $current) {
        $snapshots.Add([pscustomobject]$current)
        $current = $null
    }
}
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
$snapshots | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $Session 'world-snapshots.json') -Encoding utf8
$summary | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $Session 'world-summary.json') -Encoding utf8
$summary | Format-Table stage,game_ms,level,creatures,living,online,@{n='duplicates';e={$_.duplicateIds.Count}},@{n='offmapOnline';e={$_.onlineOtherMapIds.Count}} -AutoSize
