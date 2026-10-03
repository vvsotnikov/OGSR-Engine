param(
    [string]$InstallRoot = 'D:/Games/OGSR-Regular-Validation',
    [string]$ToolRoot = 'C:/Users/vladimir/Documents/Codex/tools/tracy',
    [ValidateRange(0,400)][int]$Count = 0,
    [ValidateRange(0,10)][int]$BudgetMs = 0,
    [switch]$CompactQueue,
    [switch]$SaveSnapshot,
    [string]$SeedAppData = 'seeds/bar-2026-10-03',
    [string]$SaveName = 'bar_center'
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/ValidationLog.ps1"
$session = & "$PSScriptRoot/Capture-Session.ps1" -InstallRoot $InstallRoot -ToolRoot $ToolRoot `
    -Mode whole-map -SeedAppData $SeedAppData -SaveName $SaveName -PrepareOnly
$path = Join-Path $session 'session.json'
$meta = Get-Content -Raw $path | ConvertFrom-Json
$meta.arguments = $meta.arguments.Replace(' -alife_metrics', '')
if ($CompactQueue) { $meta.arguments += ' -scheduler_compact' }
$meta | Add-Member regularRequested $true
$meta | Add-Member extraRequested $Count
$meta | Add-Member spawnBudgetMs $BudgetMs
$meta | Add-Member compactQueue ([bool]$CompactQueue)
$meta | Add-Member saveRequested ([bool]$SaveSnapshot)
$meta.status = 'regular-running'
foreach ($name in @('SpawnQueue.lua','RegularDriver.lua','BarStressPositions.lua','Test-SpawnQueue.lua')) {
    Copy-Item "$PSScriptRoot/$name" "$session/appdata/$name"
}
$save = if ($SaveSnapshot) { 'true' } else { 'false' }
$config = "return {count=$Count, budget_ms=$BudgetMs, save=$save, positions=dofile(getFS():update_path(`"`$app_data_root`$`", `"BarStressPositions.lua`"))}"
[IO.File]::WriteAllText("$session/appdata/regular-config.lua", $config, [Text.Encoding]::ASCII)
$engine = Join-Path $InstallRoot 'bin_experiment/xrEngine.exe'
$game = Start-Process $engine -ArgumentList $meta.arguments -WorkingDirectory $InstallRoot -PassThru
$meta | Add-Member gamePid $game.Id
$meta | ConvertTo-Json -Depth 8 | Set-Content $path -Encoding utf8
Write-Output "START count=$Count budget=$BudgetMs compact=$CompactQueue session=$session pid=$($game.Id)"
try {
    $deadline = (Get-Date).AddSeconds(240)
    while (!$game.WaitForExit(2000)) {
        if ((Get-Date) -gt $deadline) {
            $game.Refresh()
            if ($game.Path -eq $engine) { Stop-Process -Id $game.Id }
            throw 'Regular validation exceeded watchdog; own test process stopped'
        }
    }
    $logs = @(Get-ChildItem "$session/appdata/logs" -Filter '*.log')
    if ($logs.Count -ne 1) { throw 'Expected one engine log' }
    $log = [IO.File]::ReadAllText($logs[0].FullName)
    Assert-ValidationLogHealthy $log
    if ($game.ExitCode -ne 0 -or $log -match '\[regular\] FAILED' -or $log -notmatch '\[regular\] measure_end' -or $log -notmatch '\[regular\] queue_tests_passed') { throw 'Regular validation failed or incomplete' }
    if ($log -notmatch "\[regular\] create_end count=$Count " -or $log -notmatch "\[regular\] all_online count=$Count ") { throw 'Missing creation/activation evidence' }
    if ($SaveSnapshot -and ($log -notmatch 'Game regular_validation\.sav is successfully saved' -or !(Test-Path "$session/appdata/savedgames/regular_validation.sav"))) { throw 'Save not acknowledged' }
    $meta.status = 'regular-completed'
    $meta | Add-Member gameExitCode $game.ExitCode
    Write-Output "COMPLETE session=$session"
} catch {
    $meta.status = 'regular-failed'
    $meta | Add-Member failure $_.Exception.Message
    throw
} finally {
    $meta | ConvertTo-Json -Depth 8 | Set-Content $path -Encoding utf8
}
