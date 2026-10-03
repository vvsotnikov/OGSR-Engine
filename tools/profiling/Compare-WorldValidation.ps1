param([Parameter(Mandatory)][string]$Session, [Parameter(Mandatory)][string]$RestartSession)
$ErrorActionPreference = 'Stop'
$first = Get-Content -Raw "$Session/world-snapshots.json" | ConvertFrom-Json
$second = Get-Content -Raw "$RestartSession/world-snapshots.json" | ConvertFrom-Json
$baseline = @($first | Where-Object stage -eq 'save validation_bar')[-1].entities
$tests = @(
    @{name='same-process-first'; snapshot=@($first | Where-Object stage -eq 'load validation_bar')[0]},
    @{name='cold-first'; snapshot=$second[0]},
    @{name='return-last'; snapshot=$first[-1]}
)
$results = foreach ($test in $tests) {
    $after = $test.snapshot.entities
    $map = @{}; foreach ($e in $after) { $map[$e.id] = $e }
    $changes = @(foreach ($e in $baseline) {
        if ($map.ContainsKey($e.id)) {
            foreach ($field in @('section','health','flags','parent','group','graph','level')) {
                if ($e.$field -ne $map[$e.id].$field) {
                    [pscustomobject]@{id=$e.id;field=$field;before=$e.$field;after=$map[$e.id].$field}
                }
            }
        }
    })
    [pscustomobject]@{
        test=$test.name; baselineCount=$baseline.Count; afterCount=$after.Count
        missingIds=@($baseline | Where-Object { $_.id -notin $after.id } | ForEach-Object id)
        addedIds=@($after | Where-Object { $_.id -notin $baseline.id } | ForEach-Object id)
        changes=$changes
    }
}
$results | ConvertTo-Json -Depth 6 | Set-Content "$Session/world-comparison.json" -Encoding utf8
foreach ($r in $results) {
    [pscustomobject]@{ test=$r.test; before=$r.baselineCount; after=$r.afterCount; missing=$r.missingIds.Count; added=$r.addedIds.Count
        changes=(($r.changes | Group-Object field | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', ') }
}
