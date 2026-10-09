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
    $resume = & "$PSScriptRoot/Run-NpcTrip.ps1" -InstallRoot $root -Package bin_fixture -Scenario resume -ResumeSession $session -PrepareOnly
    if ((Get-Content "$resume/appdata/savedgames/npc_trip_pending.sav" -Raw).Trim() -ne 'pending' -or
        (Get-FileHash "$resume/appdata/npc-trip-ids.lua").Hash -ne (Get-FileHash "$session/appdata/npc-trip-ids.lua").Hash) { throw 'Resume did not use the pending save and its bindings' }
    $goal = & "$PSScriptRoot/Run-NpcTrip.ps1" -InstallRoot $root -Package bin_fixture -Scenario goal-save -GoalOffline -PrepareOnly
    $goalMeta = Get-Content "$goal/session.json" -Raw | ConvertFrom-Json
    if (!$goalMeta.goalOffline -or (Get-FileHash "$goal/appdata/RegularDriver.lua").Hash -ne (Get-FileHash "$PSScriptRoot/NpcGoalDriver.lua").Hash) { throw 'Wrong goal driver or mode' }
    $goalMeta.status = 'npc-completed'
    $goalMeta | ConvertTo-Json | Set-Content "$goal/session.json"
    Set-Content "$goal/appdata/savedgames/npc_trip_pending.sav" 'goal'
    Set-Content "$goal/appdata/npc-trip-ids.lua" 'return {npc=1,offline=true,stage=2}'
    $restoredGoal = & "$PSScriptRoot/Run-NpcTrip.ps1" -InstallRoot $root -Package bin_fixture -Scenario goal-resume -ResumeSession $goal -PrepareOnly
    if (!(Get-Content "$restoredGoal/session.json" -Raw | ConvertFrom-Json).goalOffline -or
        (Get-FileHash "$restoredGoal/appdata/npc-trip-ids.lua").Hash -ne (Get-FileHash "$goal/appdata/npc-trip-ids.lua").Hash) { throw 'Goal resume lost saved mode or bindings' }
    $after = @($paths | ForEach-Object { (Get-FileHash "$root/$_").Hash })
    if (($before -join ',') -ne ($after -join ',')) { throw 'Original inputs modified' }
} finally {
    if ((Resolve-Path -LiteralPath $root).Path -ne $root -or (Split-Path -Leaf $root) -notmatch '^ogsr-npc-[0-9a-f-]{36}$') { throw 'Unexpected fixture path' }
    Remove-Item -LiteralPath $root -Recurse
}
