param(
    [Parameter(Mandatory)][string]$InstallRoot,
    [Parameter(Mandatory)][string]$ToolRoot,
    [ValidatePattern('^bin_[a-zA-Z0-9_]+$')][string]$Package = 'bin_whole_lifecycle',
    [ValidateSet('distance', 'whole-map')][string]$Mode = 'distance',
    [ValidateRange(5, 300)][int]$Seconds = 60,
    [ValidateRange(1, 50)][int]$MemoryPercent = 20,
    [ValidateRange(0, 600)][int]$DelaySeconds = 30,
    [ValidatePattern('^[a-zA-Z0-9_-]+$')][string]$SaveName = 'vladimir_quicksave',
    [string]$SeedAppData = '_appdata_profiler_',
    [switch]$Diagnostics,
    [switch]$PrepareOnly
)
$ErrorActionPreference = 'Stop'
$InstallRoot = (Resolve-Path $InstallRoot).Path
$ToolRoot = (Resolve-Path $ToolRoot).Path
$repo = (Resolve-Path "$PSScriptRoot/../..").Path
$engine = Join-Path $InstallRoot "$Package/xrEngine.exe"
$capture = Join-Path $ToolRoot 'bin/tracy-capture.exe'
$seed = Join-Path $InstallRoot $SeedAppData
foreach ($required in @($engine, "$seed/savedgames/$SaveName.sav", "$InstallRoot/fsgame-profiler.ltx")) {
    if (!(Test-Path -LiteralPath $required)) { throw "Missing: $required" }
}
if (Get-Process xrEngine, tracy-capture, tracy-profiler-AVX -ErrorAction SilentlyContinue) {
    throw 'Close the existing game/profiler first so the capture connects to the intended process.'
}
if (!$PrepareOnly) {
    if (!(Test-Path $capture)) { throw 'Missing Tracy capture tool' }
    $build = Get-Content -Raw "$InstallRoot/$Package/build.json" | ConvertFrom-Json
    if (!$build.tracyEnabled) { throw 'Trace capture requires a Tracy-enabled package; use -PrepareOnly for a regular build' }
}
$id = (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss-fff') + '-' + $Mode
$session = New-Item -ItemType Directory (Join-Path $InstallRoot "captures/$id")
$appdata = New-Item -ItemType Directory "$($session.FullName)/appdata"
New-Item -ItemType Directory "$($appdata.FullName)/savedgames" | Out-Null
Copy-Item -Path "$seed/user*.ltx" -Destination $appdata.FullName
# Remove the load-screen key gate in this session only. Otherwise a timed
# unattended capture can record the waiting screen instead of gameplay.
Add-Content -LiteralPath "$($appdata.FullName)/user_ogsr.ltx" -Value "`nkeypress_on_start off" -Encoding ascii
Get-ChildItem -LiteralPath "$seed/savedgames" -File | Where-Object { $_.BaseName -eq $SaveName } |
    Copy-Item -Destination "$($appdata.FullName)/savedgames"
$fs = @(Get-Content -LiteralPath "$InstallRoot/fsgame-profiler.ltx")
$fs[0] = '$app_data_root$ = true| false| $fs_root$| captures\' + $id + '\appdata\'
$fsPath = "$($session.FullName)/fsgame.ltx"
$fs | Set-Content -LiteralPath $fsPath -Encoding ascii
# X-Ray's legacy -fsltx parser does not support quoting or spaces. Use a
# space-free path relative to InstallRoot even when InstallRoot has spaces.
$argsText = '-fsltx captures\' + $id + '\fsgame.ltx -alife_metrics'
if ($Mode -eq 'whole-map') { $argsText += ' -alife_whole_map' }
if ($Diagnostics) { $argsText += ' -alife_diagnostics' }
$argsText += " -start server($SaveName/single/alife/load) client(localhost)"
$metadata = [ordered]@{
    package = $Package; session = $id; mode = $Mode; seconds = $Seconds; memoryPercent = $MemoryPercent
    delaySeconds = $DelaySeconds; seedSave = "$seed/savedgames/$SaveName.sav"
    seedSha256 = (Get-FileHash "$seed/savedgames/$SaveName.sav").Hash
    engineSha256 = (Get-FileHash $engine).Hash
    sourceCommitAtLaunch = (& git -C $repo rev-parse HEAD)
    sourceDirtyAtLaunch = [bool](& git -C $repo status --porcelain)
    arguments = $argsText; status = 'prepared'
    diagnostics = [bool]$Diagnostics
}
if (Test-Path "$InstallRoot/$Package/build.json") {
    $metadata.build = Get-Content -Raw "$InstallRoot/$Package/build.json" | ConvertFrom-Json
}
$metadata | ConvertTo-Json -Depth 6 | Set-Content "$($session.FullName)/session.json" -Encoding utf8
if ($PrepareOnly) { Write-Output $session.FullName; return }
# This is the interactive game the user is about to play; capture itself stays hidden.
$game = Start-Process -FilePath $engine -ArgumentList $argsText -WorkingDirectory $InstallRoot -PassThru
$metadata.gamePid = $game.Id
$metadata.status = 'waiting-for-capture'
$metadata | ConvertTo-Json -Depth 6 | Set-Content "$($session.FullName)/session.json" -Encoding utf8
Write-Output "Game started. Capture begins in $DelaySeconds seconds and lasts up to $Seconds seconds. Session: $($session.FullName)"
Start-Sleep -Seconds $DelaySeconds
if ($game.HasExited) {
    $metadata.status = 'game-exited-before-capture'
    $metadata.gameExitCode = $game.ExitCode
    $metadata | ConvertTo-Json -Depth 6 | Set-Content "$($session.FullName)/session.json" -Encoding utf8
    throw 'Game exited before capture. Its log is in the session appdata directory.'
}
$captureArgs = '-a 127.0.0.1 -o "' + $session.FullName + '\capture.tracy" -s ' + $Seconds + ' -m ' + $MemoryPercent
$recorder = Start-Process -FilePath $capture -ArgumentList $captureArgs -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput "$($session.FullName)/capture.stdout.log" -RedirectStandardError "$($session.FullName)/capture.stderr.log"
$metadata.status = 'recording'
$metadata.capturePid = $recorder.Id
$metadata | ConvertTo-Json -Depth 6 | Set-Content "$($session.FullName)/session.json" -Encoding utf8
$recorder.WaitForExit()
$recorder.Refresh()
$metadata.captureExitCode = $recorder.ExitCode
$trace = Get-Item "$($session.FullName)/capture.tracy" -ErrorAction SilentlyContinue
$metadata.status = if ($recorder.ExitCode -eq 0 -and $trace -and $trace.Length -gt 0) { 'saved' } else { 'capture-failed' }
$metadata.traceBytes = if ($trace) { $trace.Length } else { 0 }
$metadata | ConvertTo-Json -Depth 6 | Set-Content "$($session.FullName)/session.json" -Encoding utf8
if ($metadata.status -ne 'saved') { throw "Capture failed; see logs in $($session.FullName)" }
Write-Output "Saved: $($trace.FullName). You can exit the game normally; this session has its own saves and logs."
