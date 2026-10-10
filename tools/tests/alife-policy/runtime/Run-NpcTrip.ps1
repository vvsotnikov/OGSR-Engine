param(
    [Parameter(Mandatory)][string]$InstallRoot,
    [Parameter(Mandatory)][ValidatePattern('^bin_[a-zA-Z0-9_]+$')][string]$Package,
    [ValidateSet('Release','Debug')][string]$Configuration = 'Debug',
    [ValidateSet('basic','interrupt','offline','switch','missing','death','mismatch','natural','elevated','boundary','far','moved','spawn-combat','save','resume','fallback','goal-cycle','goal-displaced','goal-combat','goal-switch','goal-competition','goal-save','goal-resume','goal-wait-save','goal-wait-resume','control-save','control-resume','control-meet','control-transition','perception','perception-save','perception-resume','perception-memory','corpse','corpse-revisit','corpse-mixed','corpse-static','corpse-danger','corpse-rejected','corpse-rejected-offline','corpse-combat','corpse-empty','corpse-removed','corpse-competition','corpse-offline','corpse-save','corpse-resume')][string]$Scenario = 'basic',
    [ValidateSet('whole-map','distance')][string]$Mode = 'whole-map',
    [string]$ResumeSession = '',
    [switch]$GoalOffline,
    [switch]$PrepareOnly
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/ValidationPackage.ps1"
. "$PSScriptRoot/ValidationLog.ps1"
. "$PSScriptRoot/PolicyMessages.ps1"
$InstallRoot = (Resolve-Path $InstallRoot).Path
if ($Scenario -eq 'natural' -and $Mode -ne 'distance') { throw 'Natural switching requires distance mode' }
if ($GoalOffline -and (!$Scenario.StartsWith('goal-') -or $Scenario -in @('goal-combat','goal-switch'))) { throw 'GoalOffline requires an offline-capable goal scenario' }
$engine = Join-Path $InstallRoot "$Package/xrEngine.exe"
$build = Read-ValidationPackage $engine -Configuration $Configuration
$seed = 'seeds/bar-2026-10-03'
$save = 'bar_center'
if ($Scenario -in @('resume','fallback','goal-resume','goal-wait-resume','control-resume','perception-resume','corpse-resume')) {
    if (!$ResumeSession) { throw 'Resume requires the completed save scenario' }
    $previous = Get-Content "$ResumeSession/session.json" -Raw | ConvertFrom-Json
    if ($previous.status -ne 'npc-completed' -or $previous.scenario -ne $(if ($Scenario -eq 'goal-resume') { 'goal-save' } elseif ($Scenario -eq 'goal-wait-resume') { 'goal-wait-save' } elseif ($Scenario -eq 'control-resume') { 'control-save' } elseif ($Scenario -eq 'perception-resume') { 'perception-save' } elseif ($Scenario -eq 'corpse-resume') { 'corpse-save' } else { 'save' })) { throw 'Invalid resume source' }
    if ($Scenario.StartsWith('goal-')) { $GoalOffline = [bool]$previous.goalOffline }
    $resumePath = (Resolve-Path $ResumeSession).Path
    $prefix = $InstallRoot.TrimEnd('\') + '\'
    if (!$resumePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Resume session must be inside InstallRoot' }
    $seed = Join-Path $resumePath.Substring($prefix.Length) appdata
    $save = 'npc_trip_pending'
} elseif ($ResumeSession) { throw 'ResumeSession applies only to resume' }
$session = & "$PSScriptRoot/Prepare-Session.ps1" -InstallRoot $InstallRoot -Package $Package -Mode $Mode -SeedAppData $seed -SaveName $save
$meta = Get-Content "$session/session.json" -Raw | ConvertFrom-Json
$meta | Add-Member build $build
$meta | Add-Member scenario $Scenario
$meta | Add-Member goalOffline ([bool]$GoalOffline)
$runtime = New-Item -ItemType Directory "$session/runtime"
Copy-Item "$InstallRoot/gamedata" "$runtime/gamedata" -Recurse
New-Item -ItemType Directory "$runtime/gamedata/scripts" -Force | Out-Null
Copy-Item "$PSScriptRoot/../../../../Game/Resources_SoC_1.0006/gamedata/scripts/npc_sim_bridge.script" "$runtime/gamedata/scripts/npc_sim_bridge.script"
Get-ChildItem $InstallRoot -Filter 'gamedata.db*' -File | ForEach-Object {
    New-Item -ItemType HardLink -Path "$runtime/$($_.Name)" -Target $_.FullName | Out-Null
}
$config = "$runtime/gamedata/config/misc/items.ltx"
if ((Get-Content $config -Raw).Contains('[npc_trip_stalker]')) { throw 'Fixture section already exists' }
Add-Content $config "`n[npc_trip_stalker]:stalker" -Encoding ascii
if ($Scenario -ne 'fallback') { Add-Content $config 'npc_planner = supply_trip' -Encoding ascii }
if ($Scenario -eq 'corpse-rejected-offline') { Add-Content $config 'max_item_mass = 0' -Encoding ascii }
if ($Scenario -eq 'corpse-static') { Add-Content $config "`n[npc_corpse_bandage_a]:bandage`n[npc_corpse_bandage_b]:bandage" -Encoding ascii }
if ($Scenario -eq 'elevated') { Add-Content $config "`n[npc_trip_elevated_bandage]:bandage`nuse_ai_locations = false" -Encoding ascii }
if ($Scenario.StartsWith('control-')) {
    Add-Content $config 'custom_data = scripts\npc_control.ltx' -Encoding ascii
    New-Item -ItemType Directory "$runtime/gamedata/config/scripts" -Force | Out-Null
    Copy-Item "$PSScriptRoot/npc_control.ltx" "$runtime/gamedata/config/scripts/npc_control.ltx"
}
$fs = @(Get-Content "$session/fsgame.ltx")
$lines = @(0..($fs.Count-1) | Where-Object { $fs[$_] -match '^\s*\$app_data_root\$\s*=' })
if ($lines.Count -ne 1) { throw 'Expected one appdata root' }
$fs[$lines[0]] = '$app_data_root$ = true| false| ' + ("$session/appdata/" -replace '/', '\')
$fs | Set-Content "$session/fsgame.ltx" -Encoding ascii
$meta.arguments = '-fsltx ..\fsgame.ltx'
if ($Mode -eq 'whole-map') { $meta.arguments += ' -alife_whole_map' }
if ($Scenario.StartsWith('goal-') -or $Scenario -in @('control-resume','perception-memory')) { $meta.arguments += ' -npc_sim_test' }
$meta.arguments += " -start server($save/single/alife/load) client(localhost)"
$luaConfig = "return {scenario='$Scenario',mode='$Mode',offline=$(([bool]$GoalOffline).ToString().ToLowerInvariant())}"
if ($Scenario -in @('resume','fallback','goal-resume','goal-wait-resume','control-resume','perception-resume','corpse-resume')) {
    Copy-Item "$ResumeSession/appdata/npc-trip-ids.lua" "$session/appdata/npc-trip-ids.lua"
    $luaConfig = "local ids=dofile(getFS():update_path(`"`$app_data_root`$`",`"npc-trip-ids.lua`")); ids.scenario='$Scenario'; ids.mode='$Mode'; return ids"
}
Set-Content "$session/appdata/regular-config.lua" $luaConfig -Encoding ascii
$driver = if ($Scenario.StartsWith('corpse')) { 'NpcCorpseDriver.lua' } elseif ($Scenario.StartsWith('perception')) { 'NpcPerceptionDriver.lua' } elseif ($Scenario -eq 'control-transition') { 'NpcControlTransitionDriver.lua' } elseif ($Scenario.StartsWith('control-')) { 'NpcControlDriver.lua' } elseif ($Scenario.StartsWith('goal-')) { 'NpcGoalDriver.lua' } else { 'NpcTripDriver.lua' }
Copy-Item "$PSScriptRoot/$driver" "$session/appdata/RegularDriver.lua"
$meta.status = 'npc-prepared'
$meta | ConvertTo-Json -Depth 8 | Set-Content "$session/session.json" -Encoding utf8
if ($PrepareOnly) { Write-Output $session; return }
$game = $null
try {
    $game = Start-Process $engine -ArgumentList $meta.arguments -WorkingDirectory $runtime.FullName -PassThru
    $meta.status = 'npc-running'
    $meta | Add-Member gamePid $game.Id
    Write-Output "START npc scenario=$Scenario session=$session pid=$($game.Id)"
    $deadline = (Get-Date).AddSeconds($(if ($Scenario -eq 'far') { 720 } else { 360 }))
    while (!$game.WaitForExit(2000)) { if ((Get-Date) -gt $deadline) { throw 'NPC validation timed out' } }
    $logs = @(Get-ChildItem "$session/appdata/logs" -Filter '*.log')
    if ($logs.Count -ne 1) { throw 'Expected one log' }
    $log = [IO.File]::ReadAllText($logs[0].FullName)
    Assert-ValidationLogHealthy $log
    Assert-PolicyMessages $log $Mode $(if ($Scenario -eq 'control-transition') { 4 } elseif ($Scenario -in @('corpse-offline','corpse-save','corpse-rejected-offline')) { 2 } else { 1 }) $false
    if ($game.ExitCode -ne 0 -or $log -match '\[npc fixture\] FAILED') { throw 'NPC scenario failed' }
    if ($Scenario -in @('save','goal-save','goal-wait-save','control-save','perception-save','corpse-save')) {
        if ($log -notmatch '\[npc fixture\] saved_pending' -or $log -notmatch 'Game npc_trip_pending\.sav is successfully saved' -or !(Test-Path "$session/appdata/savedgames/npc_trip_pending.sav")) { throw 'Pending trip save was not acknowledged' }
    } elseif ($log -notmatch "\[npc fixture\] complete scenario=$Scenario\b") { throw 'Missing completed trip' }
    if ($Scenario -in @('resume','goal-resume','goal-wait-resume','control-resume','perception-resume','corpse-resume') -and $log -notmatch '\[npc trip\] restore identity=') { throw 'Missing native planner restore' }
    if ($Scenario -in @('interrupt','spawn-combat','goal-combat','corpse-combat') -and ($log -notmatch '\[npc fixture\] combat_observed' -or $log -notmatch '\[npc trip\].*interrupted=1')) { throw 'Missing real planner interruption' }
    if ($Scenario -eq 'goal-switch' -and ($log -notmatch '\[npc goal fixture\] observed_offline' -or $log -notmatch '\[npc goal fixture\] returned_online')) { throw 'Missing goal representation round trip' }
    if ($Scenario -eq 'moved' -and $log -notmatch '\[npc trip\].*phase=4 reason=2') { throw 'Missing SupplyMoved failure reason' }
    if ($Scenario -eq 'goal-combat' -and $log -notmatch '\[npc goal fixture\] gift_owned_during_combat') { throw 'Gift was not observed during combat' }
    if ($Scenario -eq 'goal-displaced' -and $log -notmatch '\[npc goal fixture\] returned_after_displacement') { throw 'Missing return after displacement' }
    if ($Scenario -in @('perception','perception-save','perception-memory') -and ($log -notmatch '\[npc perception fixture\] unseen_wait' -or
        $log -notmatch '\[npc perception\] npc=' -or $log -notmatch '\[npc perception fixture\] discovered' -or $log -notmatch '\[npc perception fixture\] online_unseen')) { throw 'Missing real perception sequence' }
    if ($Scenario -eq 'perception-memory' -and $log -notmatch '\[npc perception fixture\] nonpersonal_ignored') { throw 'Missing non-personal memory rejection' }
    if ($Scenario -eq 'perception-resume' -and $log -match '\[npc perception\] npc=') { throw 'Offline continuation acquired a new sighting' }
    if ($Scenario.StartsWith('corpse') -and $Scenario -notin @('corpse-save','corpse-removed','corpse-rejected','corpse-rejected-offline') -and $log -notmatch '\[npc search\]') { throw 'Missing actual corpse inspection' }
    if ($Scenario -in @('corpse-rejected','corpse-rejected-offline')) {
        $representation = if ($Scenario -eq 'corpse-rejected-offline') { 0 } else { 1 }
        if ([regex]::Matches($log, "\[npc search\] rejected .*online=$representation reason=").Count -lt 2) { throw 'Missing native rejection in the required representation' }
    }
    if ($Scenario -eq 'corpse-mixed' -and $log -notmatch '\[npc search\].*remaining=1') { throw 'Temporarily locked loot was forgotten' }
    if ($Scenario -eq 'corpse-static' -and $log -notmatch '\[npc search\].*remaining=0') { throw 'Statically untakeable loot remained a candidate' }
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
