$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('ogsr-npc-' + [guid]::NewGuid())
New-Item -ItemType Directory $root | Out-Null
$root = (Resolve-Path $root).Path
function Get-Process { param($Name, $ErrorAction) }
function Start-Process { throw 'Prepare-only must not launch the game' }
try {
    $seed = "$root/seeds/bar-2026-10-03"
    New-Item -ItemType Directory "$root/bin_fixture", "$seed/savedgames", "$root/gamedata/config/misc" | Out-Null
    Set-Content "$root/bin_fixture/xrEngine.exe" 'fixture'
    Set-Content "$seed/savedgames/bar_center.sav" 'save'
    Set-Content "$seed/user_ogsr.ltx" 'keypress_on_start on'
    Set-Content "$root/fsgame.ltx" '$app_data_root$ = true| false| $fs_root$| original\'
    Set-Content "$root/gamedata/config/misc/items.ltx" '[original]'
    @{configuration='Debug';tracyEnabled=$false;sha256=(Get-FileHash "$root/bin_fixture/xrEngine.exe").Hash} |
        ConvertTo-Json | Set-Content "$root/bin_fixture/build.json"
    $paths = @('gamedata/config/misc/items.ltx','seeds/bar-2026-10-03/savedgames/bar_center.sav','fsgame.ltx')
    $before = @($paths | ForEach-Object { (Get-FileHash "$root/$_").Hash })
    $session = & "$PSScriptRoot/Run-NpcTrip.ps1" -InstallRoot $root -Package bin_fixture -Scenario save -PrepareOnly
    $meta = Get-Content "$session/session.json" -Raw | ConvertFrom-Json
    if ($meta.status -ne 'npc-prepared' -or $meta.PSObject.Properties['gamePid']) { throw 'Preparation claimed runtime evidence' }
    if (!(Get-Content "$session/appdata/regular-config.lua" -Raw).Contains("mode='whole-map'")) { throw 'Whole-map mode missing from driver config' }
    $distance = & "$PSScriptRoot/Run-NpcTrip.ps1" -InstallRoot $root -Package bin_fixture -Scenario mismatch -Mode distance -PrepareOnly
    if ((Get-Content "$distance/session.json" -Raw | ConvertFrom-Json).arguments -match '-alife_whole_map' -or
        !(Get-Content "$distance/appdata/regular-config.lua" -Raw).Contains("mode='distance'")) { throw 'Distance mode disagrees with engine arguments' }
    if ($meta.arguments -match '-npc_sim_test') { throw 'Ordinary trip run enabled test-only APIs' }
    if (!(Get-Content "$session/runtime/gamedata/config/misc/items.ltx" -Raw).Contains('npc_planner = supply_trip') -or
        !(Get-Content "$session/fsgame.ltx" -Raw).Contains(($session -replace '/', '\')) -or
        (Get-FileHash "$session/appdata/RegularDriver.lua").Hash -ne (Get-FileHash "$PSScriptRoot/NpcTripDriver.lua").Hash) { throw 'Trip session is not isolated' }
    $rejected = $false
    try { & "$PSScriptRoot/Run-NpcTrip.ps1" -InstallRoot $root -Package bin_fixture -Scenario resume -ResumeSession $session -PrepareOnly | Out-Null } catch { $rejected = $true }
    if (!$rejected) { throw 'Accepted an unexecuted save scenario for resume' }
    $meta.status = 'npc-completed'
    $meta | ConvertTo-Json | Set-Content "$session/session.json"
    Set-Content "$session/appdata/savedgames/npc_trip_pending.sav" 'pending'
    Set-Content "$session/appdata/npc-trip-ids.lua" 'return {npc=1,supply=2}'
    $resume = & "$PSScriptRoot/Run-NpcTrip.ps1" -InstallRoot $root -Package bin_fixture -Scenario resume -ResumeSession $session -Mode distance -PrepareOnly
    if (!(Get-Content "$resume/appdata/regular-config.lua" -Raw).Contains("ids.mode='distance'")) { throw 'Resume lost requested distance mode' }
    if ((Get-Content "$resume/appdata/savedgames/npc_trip_pending.sav" -Raw).Trim() -ne 'pending' -or
        (Get-FileHash "$resume/appdata/npc-trip-ids.lua").Hash -ne (Get-FileHash "$session/appdata/npc-trip-ids.lua").Hash) { throw 'Resume did not use the pending save and its bindings' }
    $goal = & "$PSScriptRoot/Run-NpcTrip.ps1" -InstallRoot $root -Package bin_fixture -Scenario goal-save -GoalOffline -PrepareOnly
    $goalMeta = Get-Content "$goal/session.json" -Raw | ConvertFrom-Json
    if (!$goalMeta.goalOffline -or $goalMeta.arguments -notmatch '-npc_sim_test' -or
        (Get-FileHash "$goal/appdata/RegularDriver.lua").Hash -ne (Get-FileHash "$PSScriptRoot/NpcGoalDriver.lua").Hash) { throw 'Wrong goal driver or mode' }
    $goalMeta.status = 'npc-completed'
    $goalMeta | ConvertTo-Json | Set-Content "$goal/session.json"
    Set-Content "$goal/appdata/savedgames/npc_trip_pending.sav" 'goal'
    Set-Content "$goal/appdata/npc-trip-ids.lua" 'return {npc=1,offline=true,stage=2}'
    $restoredGoal = & "$PSScriptRoot/Run-NpcTrip.ps1" -InstallRoot $root -Package bin_fixture -Scenario goal-resume -ResumeSession $goal -PrepareOnly
    if (!(Get-Content "$restoredGoal/session.json" -Raw | ConvertFrom-Json).goalOffline -or
        (Get-FileHash "$restoredGoal/appdata/npc-trip-ids.lua").Hash -ne (Get-FileHash "$goal/appdata/npc-trip-ids.lua").Hash) { throw 'Goal resume lost saved mode or bindings' }
    $perception = & "$PSScriptRoot/Run-NpcTrip.ps1" -InstallRoot $root -Package bin_fixture -Scenario perception-save -PrepareOnly
    $perceptionMeta = Get-Content "$perception/session.json" -Raw | ConvertFrom-Json
    if ($perceptionMeta.arguments -match '-npc_sim_test' -or
        (Get-FileHash "$perception/appdata/RegularDriver.lua").Hash -ne (Get-FileHash "$PSScriptRoot/NpcPerceptionDriver.lua").Hash) { throw 'Perception must use ordinary gameplay APIs' }
    $memory = & "$PSScriptRoot/Run-NpcTrip.ps1" -InstallRoot $root -Package bin_fixture -Scenario perception-memory -PrepareOnly
    if ((Get-Content "$memory/session.json" -Raw | ConvertFrom-Json).arguments -notmatch '-npc_sim_test' -or
        (Get-FileHash "$memory/appdata/RegularDriver.lua").Hash -ne (Get-FileHash "$PSScriptRoot/NpcPerceptionDriver.lua").Hash) { throw 'Missing native memory stimulus scenario' }
    $perceptionMeta.status = 'npc-completed'
    $perceptionMeta | ConvertTo-Json | Set-Content "$perception/session.json"
    Set-Content "$perception/appdata/savedgames/npc_trip_pending.sav" 'perception'
    Set-Content "$perception/appdata/npc-trip-ids.lua" 'return {npc=1,item=2,stage=3}'
    $perceptionResume = & "$PSScriptRoot/Run-NpcTrip.ps1" -InstallRoot $root -Package bin_fixture -Scenario perception-resume -ResumeSession $perception -PrepareOnly
    if ((Get-Content "$perceptionResume/appdata/savedgames/npc_trip_pending.sav" -Raw).Trim() -ne 'perception' -or
        (Get-FileHash "$perceptionResume/appdata/npc-trip-ids.lua").Hash -ne (Get-FileHash "$perception/appdata/npc-trip-ids.lua").Hash) { throw 'Perception resume lost the actual learned save' }
    $after = @($paths | ForEach-Object { (Get-FileHash "$root/$_").Hash })
    if (($before -join ',') -ne ($after -join ',')) { throw 'Original inputs modified' }
} finally {
    if ((Resolve-Path -LiteralPath $root).Path -ne $root -or (Split-Path -Leaf $root) -notmatch '^ogsr-npc-[0-9a-f-]{36}$') { throw 'Unexpected fixture path' }
    Remove-Item -LiteralPath $root -Recurse
}
