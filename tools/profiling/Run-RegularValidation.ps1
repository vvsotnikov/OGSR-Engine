param(
    [string]$InstallRoot = 'D:/Games/OGSR-Regular-Validation',
    [string]$ToolRoot = 'C:/Users/vladimir/Documents/Codex/tools/tracy',
    [ValidateRange(0,400)][int]$Count = 0,
    [ValidateRange(0,10)][int]$BudgetMs = 0,
    [switch]$CompactQueue,
    [switch]$SaveSnapshot,
    [ValidateSet('bin_experiment','bin_policy','bin_activation','bin_activation_tracy','bin_reconcile')][string]$Package = 'bin_experiment',
    [switch]$ReconcileMetrics,
    [switch]$Transitions,
    [switch]$ActivationQueue,
    [switch]$CaptureTrace,
    [switch]$Metrics,
    [switch]$SavePending,
    [string]$VerifySession = '',
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
if ($Transitions -and ($Count -ne 0 -or $Eligibility -or $SavePending -or $SaveSnapshot -or $VerifySession -or $CaptureTrace)) { throw 'Transition fixture must run by itself' }
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
if ($ActivationQueue) { $meta.arguments += ' -alife_activation_queue' }
if ($Metrics) { $meta.arguments += ' -alife_metrics' }
if ($ReconcileMetrics) { $meta.arguments += ' -alife_reconcile_metrics' }
$meta | Add-Member reconcileMetrics ([bool]$ReconcileMetrics)
$meta | Add-Member transitionsRequested ([bool]$Transitions)
if ($CaptureTrace -and !$meta.build.tracyEnabled) { throw 'Trace requires a Tracy-enabled package' }
$meta | Add-Member activationQueue ([bool]$ActivationQueue)
$meta | Add-Member traceRequested ([bool]$CaptureTrace)
$collector = $null
$meta | Add-Member regularRequested $true
$meta | Add-Member extraRequested $Count
$meta | Add-Member spawnBudgetMs $BudgetMs
$meta | Add-Member compactQueue ([bool]$CompactQueue)
$meta | Add-Member saveRequested ([bool]$SaveSnapshot)
$meta.status = 'regular-running'
foreach ($name in @('SpawnQueue.lua','RegularDriver.lua','BarStressPositions.lua','Test-SpawnQueue.lua','Test-Eligibility.lua','TransitionDriver.lua')) {
    Copy-Item "$PSScriptRoot/$name" "$session/appdata/$name"
}
$save = if ($SaveSnapshot) { 'true' } else { 'false' }
$eligibilityValue = if ($Eligibility) { 'true' } else { 'false' }
$pendingValue = if ($SavePending) { 'true' } else { 'false' }
$transitionValue = if ($Transitions) { 'true' } else { 'false' }
$meta | Add-Member savePendingRequested ([bool]$SavePending)
$verifyIds = @()
if ($VerifySession) {
    $sourceMeta = Get-Content -Raw "$VerifySession/session.json" | ConvertFrom-Json
    if ($sourceMeta.status -ne 'regular-completed') { throw 'Verify source session is incomplete' }
    $sourceLog = Get-Content -Raw (Get-ChildItem "$VerifySession/appdata/logs" -Filter '*.log' | Select-Object -First 1).FullName
    $verifyIds = @([regex]::Matches($sourceLog,'\[regular spawn\] index=\d+ id=(\d+)') | ForEach-Object { [int]$_.Groups[1].Value })
    if ($verifyIds.Count -eq 0 -or $verifyIds.Count -ne $sourceMeta.extraRequested -or @($verifyIds | Select-Object -Unique).Count -ne $verifyIds.Count) { throw 'Invalid saved population evidence' }
}
$meta | Add-Member verifyIds $verifyIds
$config = "return {count=$Count, budget_ms=$BudgetMs, save=$save, transitions=$transitionValue, save_pending=$pendingValue, eligibility=$eligibilityValue, verify_ids={$($verifyIds -join ',')}, positions=dofile(getFS():update_path(`"`$app_data_root`$`", `"BarStressPositions.lua`"))}"
[IO.File]::WriteAllText("$session/appdata/regular-config.lua", $config, [Text.Encoding]::ASCII)
$game = Start-Process $engine -ArgumentList $meta.arguments -WorkingDirectory $InstallRoot -PassThru
$meta | Add-Member gamePid $game.Id
$meta | ConvertTo-Json -Depth 8 | Set-Content $path -Encoding utf8
Write-Output "START count=$Count budget=$BudgetMs compact=$CompactQueue session=$session pid=$($game.Id)"
try {
    $deadline = (Get-Date).AddSeconds(240)
    while (!$game.WaitForExit(2000)) {
        if ($CaptureTrace -and !$collector) {
            $logFile = Get-ChildItem "$session/appdata/logs" -Filter '*.log' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($logFile) {
                $stream = [IO.File]::Open($logFile.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
                $reader = [IO.StreamReader]::new($stream)
                try { $live = $reader.ReadToEnd() } finally { $reader.Dispose() }
                if ($live -match '\[regular\] ready') {
                    $captureArgs = '-a 127.0.0.1 -o "' + $session + '\capture.tracy" -s 75 -m 20'
                    $collector = Start-Process "$ToolRoot/bin/tracy-capture.exe" -ArgumentList $captureArgs -WindowStyle Hidden -PassThru `
                        -RedirectStandardOutput "$session/capture.stdout.log" -RedirectStandardError "$session/capture.stderr.log"
                    Write-Output "TRACE session=$session pid=$($collector.Id)"
                }
            }
        }
        if ((Get-Date) -gt $deadline) {
            $game.Refresh()
            if ($game.Path -eq $engine) { Stop-Process -Id $game.Id }
            throw 'Regular validation exceeded watchdog; own test process stopped'
        }
    }
    $logs = @(Get-ChildItem "$session/appdata/logs" -Filter '*.log')
    if ($CaptureTrace) {
        if (!$collector -or !$collector.WaitForExit(60000) -or $collector.ExitCode -ne 0 -or !(Test-Path "$session/capture.tracy")) { throw 'Trace capture failed or incomplete' }
        $meta | Add-Member traceBytes (Get-Item "$session/capture.tracy").Length
    }
    if ($logs.Count -ne 1) { throw 'Expected one engine log' }
    $log = [IO.File]::ReadAllText($logs[0].FullName)
    Assert-ValidationLogHealthy $log
    if ($ReconcileMetrics -and $log -notmatch '\[ALife reconcile\].*sampled=1') { throw 'Reconciliation timing was not exercised' }
    if ($Transitions) {
        $arrivals = @([regex]::Matches($log, '\[transition\] arrived phase=\d map=\w+') | ForEach-Object Value)
        $expected = '[transition] arrived phase=1 map=l05_bar|[transition] arrived phase=2 map=l02_garbage|[transition] arrived phase=3 map=l05_bar'
        if (($arrivals -join '|') -ne $expected -or $game.ExitCode -ne 0 -or $log -match '\[transition\] FAILED' -or $log -notmatch '\[transition\] complete' -or $log -notmatch 'Game reconcile_roundtrip\.sav is successfully saved') { throw 'Level roundtrip failed or unacknowledged' }
        $meta.status = 'transition-completed'
        $meta | Add-Member gameExitCode $game.ExitCode
        Write-Output "COMPLETE transitions session=$session"
        return
    }
    if ($ActivationQueue -and $Mode -eq 'whole-map' -and $log -notmatch 'ALife activation queue: enabled') { throw 'Executable did not acknowledge activation queue' }
    if ($verifyIds.Count -and $log -notmatch "\[regular\] verified_restored count=$($verifyIds.Count)\b") { throw 'Restored population not verified' }
    if ($SavePending -and ($log -notmatch '\[regular\] save_pending offline=[1-9]' -or $log -notmatch 'Game activation_pending\.sav is successfully saved' -or !(Test-Path "$session/appdata/savedgames/activation_pending.sav"))) { throw 'Pending activation save not acknowledged' }
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
