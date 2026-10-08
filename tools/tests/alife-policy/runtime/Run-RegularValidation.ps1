param(
    [Parameter(Mandatory)][string]$InstallRoot,
    [ValidateRange(0,400)][int]$Count = 0,
    [ValidateRange(0,10)][int]$BudgetMs = 0,
    [switch]$SaveSnapshot,
    [switch]$ServiceTrace,
    [switch]$ServiceSlices,
    [switch]$ServiceLifecycle,
    [switch]$FrameTimes,
    [switch]$PrepareOnly,
    [ValidatePattern('^bin_[a-zA-Z0-9_]+$')][string]$Package = 'bin_whole_lifecycle',
    [switch]$Transitions,
    [string]$VerifySession = '',
    [switch]$Eligibility,
    [switch]$DistanceControl,
    [ValidateSet('distance','whole-map')][string]$Mode = 'whole-map',
    [string]$SeedAppData = 'seeds/bar-2026-10-03',
    [string]$SaveName = 'bar_center'
)
$ErrorActionPreference = 'Stop'
if (([int][bool]$ServiceTrace + [int][bool]$ServiceSlices + [int][bool]$ServiceLifecycle) -gt 1) { throw 'Choose one service recording mode' }
. "$PSScriptRoot/ValidationLog.ps1"
. "$PSScriptRoot/ValidationPackage.ps1"
. "$PSScriptRoot/PolicyMessages.ps1"
$engine = Join-Path $InstallRoot "$Package/xrEngine.exe"
if (!(Test-Path $engine) -or !(Test-Path "$InstallRoot/$Package/build.json")) { throw "Missing package or manifest: $engine" }
$build = Read-ValidationPackage $engine
if ($Mode -eq 'distance' -and $Eligibility) { throw 'Eligibility fixture requires whole-map mode' }
if ($Transitions -and ($Count -ne 0 -or $Eligibility -or $SaveSnapshot -or $VerifySession)) { throw 'Transition fixture must run by itself' }
$session = & "$PSScriptRoot/Prepare-Session.ps1" -InstallRoot $InstallRoot `
    -Package $Package -Mode $Mode -SeedAppData $SeedAppData -SaveName $SaveName
$path = Join-Path $session 'session.json'
$meta = Get-Content -Raw $path | ConvertFrom-Json
$meta.engineSha256 = $build.sha256
$meta | Add-Member -NotePropertyName build -NotePropertyValue $build
$meta.package = $Package
$meta | Add-Member distanceControl ([bool]$DistanceControl)
$meta | Add-Member eligibilityRequested ([bool]$Eligibility)
$meta | Add-Member transitionsRequested ([bool]$Transitions)
$meta | Add-Member regularRequested $true
$meta | Add-Member extraRequested $Count
$meta | Add-Member spawnBudgetMs $BudgetMs
$meta | Add-Member saveRequested ([bool]$SaveSnapshot)
$meta.status = 'regular-prepared'
if ($ServiceTrace) { $meta.arguments += ' -alife_service_trace' }
if ($ServiceSlices) { $meta.arguments += ' -alife_service_slices' }
if ($ServiceLifecycle) { $meta.arguments += ' -alife_service_lifecycle' }
$meta | Add-Member serviceLifecycle ([bool]$ServiceLifecycle)
$meta | Add-Member serviceSlices ([bool]$ServiceSlices)
$meta | Add-Member serviceTrace ([bool]$ServiceTrace)
$meta | Add-Member frameTimes ([bool]$FrameTimes)
foreach ($name in @('SpawnQueue.lua','RegularDriver.lua','BarStressPositions.lua','Test-Eligibility.lua','TransitionDriver.lua','PolicyProbe.lua')) {
    Copy-Item "$PSScriptRoot/$name" "$session/appdata/$name"
}
$save = if ($SaveSnapshot) { 'true' } else { 'false' }
$eligibilityValue = if ($Eligibility) { 'true' } else { 'false' }
$transitionValue = if ($Transitions) { 'true' } else { 'false' }
$verifyIds = @()
if ($VerifySession) {
    $sourceMeta = Get-Content -Raw "$VerifySession/session.json" | ConvertFrom-Json
    if ($sourceMeta.status -ne 'regular-completed') { throw 'Verify source session is incomplete' }
    $sourceLogs = @(Get-ChildItem "$VerifySession/appdata/logs" -Filter '*.log')
    if ($sourceLogs.Count -ne 1) { throw 'Expected one source session log' }
    $sourceLog = [IO.File]::ReadAllText($sourceLogs[0].FullName)
    $verifyIds = @([regex]::Matches($sourceLog,'\[regular spawn\] index=\d+ id=(\d+)') | ForEach-Object { [int]$_.Groups[1].Value })
    if ($verifyIds.Count -eq 0 -or $verifyIds.Count -ne $sourceMeta.extraRequested -or @($verifyIds | Select-Object -Unique).Count -ne $verifyIds.Count) { throw 'Invalid saved population evidence' }
}
$meta | Add-Member verifyIds $verifyIds
$controlValue = if ($DistanceControl) { 'true' } else { 'false' }
$frameValue = if ($FrameTimes) { 'true' } else { 'false' }
$config = "return {frame_times=$frameValue,mode='$Mode', distance_control=$controlValue, count=$Count, budget_ms=$BudgetMs, save=$save, transitions=$transitionValue, eligibility=$eligibilityValue, verify_ids={$($verifyIds -join ',')}, positions=dofile(getFS():update_path(`"`$app_data_root`$`", `"BarStressPositions.lua`"))}"
[IO.File]::WriteAllText("$session/appdata/regular-config.lua", $config, [Text.Encoding]::ASCII)
$meta | ConvertTo-Json -Depth 8 | Set-Content $path -Encoding utf8
if ($PrepareOnly) {
    Write-Output $session
    return
}
try {
    $game = Start-Process $engine -ArgumentList $meta.arguments -WorkingDirectory $InstallRoot -PassThru
    $meta.status = 'regular-running'
    $meta | Add-Member gamePid $game.Id
    $meta | ConvertTo-Json -Depth 8 | Set-Content $path -Encoding utf8
    Write-Output "START count=$Count budget=$BudgetMs session=$session pid=$($game.Id)"
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
    $loads = if ($Transitions) { 3 } else { 1 }
    Assert-PolicyMessages $log $Mode $loads ([bool]($DistanceControl -or $Transitions))
    if ($Transitions) {
        $arrivals = @([regex]::Matches($log, '\[transition\] arrived phase=\d map=\w+') | ForEach-Object Value)
        $expected = '[transition] arrived phase=1 map=l05_bar|[transition] arrived phase=2 map=l02_garbage|[transition] arrived phase=3 map=l05_bar'
        if (($arrivals -join '|') -ne $expected -or $game.ExitCode -ne 0 -or $log -match '\[transition\] FAILED' -or $log -notmatch '\[transition\] complete' -or $log -notmatch 'Game reconcile_roundtrip\.sav is successfully saved') { throw 'Level roundtrip failed or unacknowledged' }
        if (@([regex]::Matches($log, '\[transition\] policy_passed phase=')).Count -ne 3) { throw 'Missing policy evidence after arrivals' }
        $meta.status = 'transition-completed'
        $meta | Add-Member gameExitCode $game.ExitCode
        Write-Output "COMPLETE transitions session=$session"
        return
    }
    if ($verifyIds.Count -and $log -notmatch "\[regular\] verified_restored count=$($verifyIds.Count)\b") { throw 'Restored population not verified' }
    if ($Eligibility -and $log -notmatch '\[regular\] eligibility_passed') { throw 'Eligibility test incomplete' }
    if ($game.ExitCode -ne 0 -or $log -match '\[regular\] FAILED' -or $log -notmatch '\[regular\] measure_end') { throw 'Regular validation failed or incomplete' }
    if ($log -notmatch "\[regular\] create_end count=$Count ") { throw 'Missing creation/activation evidence' }
    if ($SaveSnapshot -and ($log -notmatch 'Game regular_validation\.sav is successfully saved' -or !(Test-Path "$session/appdata/savedgames/regular_validation.sav"))) { throw 'Save not acknowledged' }
    if ($Count -and $DistanceControl -and $log -notmatch '\[regular\] distance_control_passed') { throw 'Missing distant population control' }
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
