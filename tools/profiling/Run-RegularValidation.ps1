param(
    [string]$InstallRoot = 'D:/Games/OGSR-Regular-Validation',
    [string]$ToolRoot = 'C:/Users/vladimir/Documents/Codex/tools/tracy',
    [ValidateRange(0,400)][int]$Count = 0,
    [ValidateRange(0,10)][int]$BudgetMs = 0,
    [switch]$CompactQueue,
    [switch]$SaveSnapshot,
    [ValidateSet('bin_experiment','bin_policy')][string]$Package = 'bin_experiment',
    [switch]$Eligibility,
    [ValidateSet('distance','whole-map')][string]$Mode = 'whole-map',
    [string]$SeedAppData = 'seeds/bar-2026-10-03',
    [string]$SaveName = 'bar_center'
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/ValidationLog.ps1"
$engine = Join-Path $InstallRoot "$Package/xrEngine.exe"
if (!(Test-Path $engine) -or !(Test-Path "$InstallRoot/$Package/build.json")) { throw "Missing package or manifest: $engine" }
if ($Mode -eq 'distance' -and ($Count -ne 0 -or $Eligibility)) { throw 'Population and eligibility fixtures require whole-map mode' }
$session = & "$PSScriptRoot/Capture-Session.ps1" -InstallRoot $InstallRoot -ToolRoot $ToolRoot `
    -Mode $Mode -SeedAppData $SeedAppData -SaveName $SaveName -PrepareOnly
$path = Join-Path $session 'session.json'
$meta = Get-Content -Raw $path | ConvertFrom-Json
$meta.arguments = $meta.arguments.Replace(' -alife_metrics', '')
$meta.engineSha256 = (Get-FileHash $engine).Hash
$meta.build = Get-Content -Raw "$InstallRoot/$Package/build.json" | ConvertFrom-Json
$meta | Add-Member package $Package
$meta | Add-Member eligibilityRequested ([bool]$Eligibility)
if ($CompactQueue) { $meta.arguments += ' -scheduler_compact' }
$meta | Add-Member regularRequested $true
$meta | Add-Member extraRequested $Count
$meta | Add-Member spawnBudgetMs $BudgetMs
$meta | Add-Member compactQueue ([bool]$CompactQueue)
$meta | Add-Member saveRequested ([bool]$SaveSnapshot)
$meta.status = 'regular-running'
foreach ($name in @('SpawnQueue.lua','RegularDriver.lua','BarStressPositions.lua','Test-SpawnQueue.lua','Test-Eligibility.lua')) {
    Copy-Item "$PSScriptRoot/$name" "$session/appdata/$name"
}
$save = if ($SaveSnapshot) { 'true' } else { 'false' }
$eligibilityValue = if ($Eligibility) { 'true' } else { 'false' }
$config = "return {count=$Count, budget_ms=$BudgetMs, save=$save, eligibility=$eligibilityValue, positions=dofile(getFS():update_path(`"`$app_data_root`$`", `"BarStressPositions.lua`"))}"
[IO.File]::WriteAllText("$session/appdata/regular-config.lua", $config, [Text.Encoding]::ASCII)
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
    if ($Eligibility -and $log -notmatch '\[regular\] eligibility_passed') { throw 'Eligibility test incomplete' }
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
