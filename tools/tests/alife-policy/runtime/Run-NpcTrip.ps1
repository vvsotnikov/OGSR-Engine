param(
    [Parameter(Mandatory)][string]$InstallRoot,
    [Parameter(Mandatory)][ValidatePattern('^bin_[a-zA-Z0-9_]+$')][string]$Package,
    [ValidateSet('Release','Debug')][string]$Configuration = 'Debug',
    [ValidateSet('basic','interrupt','offline','switch','missing','death','save','resume')][string]$Scenario = 'basic',
    [string]$ResumeSession = '',
    [switch]$PrepareOnly
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/ValidationPackage.ps1"
. "$PSScriptRoot/ValidationLog.ps1"
. "$PSScriptRoot/PolicyMessages.ps1"
$InstallRoot = (Resolve-Path $InstallRoot).Path
$engine = Join-Path $InstallRoot "$Package/xrEngine.exe"
$build = Read-ValidationPackage $engine -Configuration $Configuration
$seed = 'seeds/bar-2026-10-03'
$save = 'bar_center'
if ($Scenario -eq 'resume') {
    if (!$ResumeSession) { throw 'Resume requires the completed save scenario' }
    $previous = Get-Content "$ResumeSession/session.json" -Raw | ConvertFrom-Json
    if ($previous.status -ne 'npc-completed' -or $previous.scenario -ne 'save') { throw 'Invalid resume source' }
    $resumePath = (Resolve-Path $ResumeSession).Path
    $prefix = $InstallRoot.TrimEnd('\') + '\'
    if (!$resumePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Resume session must be inside InstallRoot' }
    $seed = Join-Path $resumePath.Substring($prefix.Length) appdata
    $save = 'npc_trip_pending'
} elseif ($ResumeSession) { throw 'ResumeSession applies only to resume' }
$session = & "$PSScriptRoot/Prepare-Session.ps1" -InstallRoot $InstallRoot -Package $Package -Mode whole-map -SeedAppData $seed -SaveName $save
$meta = Get-Content "$session/session.json" -Raw | ConvertFrom-Json
$meta | Add-Member build $build
$meta | Add-Member scenario $Scenario
$runtime = New-Item -ItemType Directory "$session/runtime"
Copy-Item "$InstallRoot/gamedata" "$runtime/gamedata" -Recurse
Get-ChildItem $InstallRoot -Filter 'gamedata.db*' -File | ForEach-Object {
    New-Item -ItemType HardLink -Path "$runtime/$($_.Name)" -Target $_.FullName | Out-Null
}
$config = "$runtime/gamedata/config/misc/items.ltx"
if ((Get-Content $config -Raw).Contains('[npc_trip_stalker]')) { throw 'Fixture section already exists' }
Add-Content $config "`n[npc_trip_stalker]:stalker`nnpc_planner = supply_trip`n" -Encoding ascii
$fs = @(Get-Content "$session/fsgame.ltx")
$lines = @(0..($fs.Count-1) | Where-Object { $fs[$_] -match '^\s*\$app_data_root\$\s*=' })
if ($lines.Count -ne 1) { throw 'Expected one appdata root' }
$fs[$lines[0]] = '$app_data_root$ = true| false| ' + ("$session/appdata/" -replace '/', '\')
$fs | Set-Content "$session/fsgame.ltx" -Encoding ascii
$meta.arguments = '-fsltx ..\fsgame.ltx -alife_whole_map' + " -start server($save/single/alife/load) client(localhost)"
$luaConfig = "return {scenario='$Scenario'}"
if ($Scenario -eq 'resume') {
    Copy-Item "$ResumeSession/appdata/npc-trip-ids.lua" "$session/appdata/npc-trip-ids.lua"
    $luaConfig = "local ids=dofile(getFS():update_path(`"`$app_data_root`$`",`"npc-trip-ids.lua`")); ids.scenario='resume'; return ids"
}
Set-Content "$session/appdata/regular-config.lua" $luaConfig -Encoding ascii
Copy-Item "$PSScriptRoot/NpcTripDriver.lua" "$session/appdata/RegularDriver.lua"
$meta.status = 'npc-prepared'
$meta | ConvertTo-Json -Depth 8 | Set-Content "$session/session.json" -Encoding utf8
if ($PrepareOnly) { Write-Output $session; return }
$game = $null
try {
    $game = Start-Process $engine -ArgumentList $meta.arguments -WorkingDirectory $runtime.FullName -PassThru
    $meta.status = 'npc-running'
    $meta | Add-Member gamePid $game.Id
    Write-Output "START npc scenario=$Scenario session=$session pid=$($game.Id)"
    $deadline = (Get-Date).AddSeconds(360)
    while (!$game.WaitForExit(2000)) { if ((Get-Date) -gt $deadline) { throw 'NPC validation timed out' } }
    $logs = @(Get-ChildItem "$session/appdata/logs" -Filter '*.log')
    if ($logs.Count -ne 1) { throw 'Expected one log' }
    $log = [IO.File]::ReadAllText($logs[0].FullName)
    Assert-ValidationLogHealthy $log
    Assert-PolicyMessages $log whole-map 1 $false
    if ($game.ExitCode -ne 0 -or $log -match '\[npc fixture\] FAILED') { throw 'NPC scenario failed' }
    if ($Scenario -eq 'save') {
        if ($log -notmatch '\[npc fixture\] saved_pending' -or $log -notmatch 'Game npc_trip_pending\.sav is successfully saved' -or !(Test-Path "$session/appdata/savedgames/npc_trip_pending.sav")) { throw 'Pending trip save was not acknowledged' }
    } elseif ($log -notmatch "\[npc fixture\] complete scenario=$Scenario\b") { throw 'Missing completed trip' }
    if ($Scenario -eq 'resume' -and $log -notmatch '\[npc trip\] restore identity=') { throw 'Missing native planner restore' }
    if ($Scenario -eq 'interrupt' -and ($log -notmatch '\[npc fixture\] combat_observed' -or $log -notmatch '\[npc trip\].*interrupted=1')) { throw 'Missing real planner interruption' }
    $meta.status = 'npc-completed'
    Write-Output "COMPLETE npc scenario=$Scenario session=$session"
} catch {
    $meta.status = 'npc-failed'
    $meta | Add-Member failure $_.Exception.Message
    throw
} finally {
    if ($game -and !$game.HasExited) { Stop-Process -Id $game.Id; $game.WaitForExit() }
    if ($game) { $meta | Add-Member gameExitCode $game.ExitCode -Force }
    $meta | ConvertTo-Json -Depth 8 | Set-Content "$session/session.json" -Encoding utf8
}
