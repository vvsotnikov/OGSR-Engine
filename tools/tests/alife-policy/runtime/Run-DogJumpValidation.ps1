param(
    [Parameter(Mandatory)][string]$InstallRoot,
    [Parameter(Mandatory)][ValidatePattern('^bin_[a-zA-Z0-9_]+$')][string]$Package,
    [ValidateSet('default','explicit','override','damage','missing','empty','fallback','snork','pseudodog','chimera')][string]$Case = 'default',
    [ValidateSet('Debug','Release')][string]$Configuration = 'Debug',
    [string]$SeedAppData = 'seeds/bar-2026-10-03',
    [ValidateRange(1,86400)][int]$TimeoutSeconds = 240,
    [switch]$PrepareOnly
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/ValidationPackage.ps1"
. "$PSScriptRoot/ValidationLog.ps1"
. "$PSScriptRoot/DogJumpLog.ps1"
$InstallRoot = (Resolve-Path -LiteralPath $InstallRoot).Path
$engine = Join-Path $InstallRoot "$Package/xrEngine.exe"
$build = Read-ValidationPackage -Engine $engine -Configuration $Configuration
if (!(Get-Content "$InstallRoot/gamedata/scripts/_g.script" -Raw).Contains('regular-config.lua')) {
    throw 'Use an isolated installation prepared by Prepare-RegularValidation.ps1'
}
$session = & "$PSScriptRoot/Prepare-Session.ps1" -InstallRoot $InstallRoot -Package $Package -Mode whole-map -SeedAppData $SeedAppData -SaveName bar_center
$meta = Get-Content "$session/session.json" -Raw | ConvertFrom-Json
$meta | Add-Member build $build
$meta | Add-Member case $Case
$meta | Add-Member configuration $Configuration
$meta | Add-Member timeoutSeconds $TimeoutSeconds
$runtime = New-Item -ItemType Directory "$session/runtime"
Copy-Item "$InstallRoot/gamedata" "$runtime/gamedata" -Recurse
Get-ChildItem $InstallRoot -Filter 'gamedata.db*' -File | ForEach-Object {
    New-Item -ItemType HardLink -Path "$runtime/$($_.Name)" -Target $_.FullName | Out-Null
}
$section = "validation_jump_$Case"
$config = @'

[validation_jump_default]:dog_normal
immunities_sect = validation_jump_immunities
[validation_jump_immunities]
burn_immunity = 0
strike_immunity = 0
shock_immunity = 0
wound_immunity = 0
radiation_immunity = 0
telepatic_immunity = 0
chemical_burn_immunity = 0
explosion_immunity = 0
fire_wound_immunity = 0
[validation_jump_explicit]:validation_jump_default
anim_jump_ataka_02 = jump_right_0
[validation_jump_override]:validation_jump_explicit
attack_params = validation_jump_parameters
[validation_jump_parameters]
stand_attack_0 = 0.35,0.11,31,1,0.1,0,-0.5,0.5,-1,1,1.8
jump_right_0 = 0.45,0.37,47,1,0.1,0,-0.5,0.5,-1,1,1.8
[validation_jump_damage]:validation_jump_explicit
jump_attack_params_anim = stand_attack_1
attack_params = validation_jump_damage_parameters
[validation_jump_damage_parameters]
stand_attack_0 = 0.35,0.11,31,1,0.1,0,-0.5,0.5,-1,1,1.8
stand_attack_1 = 0.45,0.37,47,1,0.1,0,-0.5,0.5,-1,1,1.8
[validation_jump_missing]:validation_jump_override
jump_attack_params_anim = jump_right_0
attack_params = validation_jump_missing_parameters
[validation_jump_missing_parameters]
stand_attack_0 = 0.35,0.11,31,1,0.1,0,-0.5,0.5,-1,1,1.8
[validation_jump_empty]:validation_jump_missing
attack_params = validation_jump_empty_parameters
[validation_jump_empty_parameters]
[validation_jump_fallback]:validation_jump_default
attack_params = validation_jump_fallback_parameters
[validation_jump_fallback_parameters]
stand_attack_1 = 0.35,0.11,31,1,0.1,0,-0.5,0.5,-1,1,1.8
[validation_jump_snork]:snork_normal
attack_params = validation_jump_missing_parameters
[validation_jump_pseudodog]:pseudodog_normal
attack_params = validation_jump_missing_parameters
; The unused SoC chimera base lacks ALife defaults; retain its class/model but
; supply missing common settings from the complete dog section.
[validation_jump_chimera]:dog_normal,m_chimera_e
attack_params = validation_jump_missing_parameters
'@
if ((Get-Content "$runtime/gamedata/config/misc/items.ltx" -Raw).Contains('[validation_jump_default]')) {
    throw 'Dog fixture sections already exist'
}
Add-Content "$runtime/gamedata/config/misc/items.ltx" $config -Encoding ascii
$fs = @(Get-Content "$session/fsgame.ltx")
$indices = @(0..($fs.Count-1) | Where-Object { $fs[$_] -match '^\s*\$app_data_root\$\s*=' })
if ($indices.Count -ne 1) { throw 'Expected one appdata root' }
$fs[$indices[0]] = '$app_data_root$ = true| false| ' + ("$session/appdata/" -replace '/', '\')
$fs | Set-Content "$session/fsgame.ltx" -Encoding ascii
$meta.arguments = '-fsltx ..\fsgame.ltx -alife_whole_map -dog_jump_probe -start server(bar_center/single/alife/load) client(localhost)'
Set-Content "$session/appdata/regular-config.lua" "return {section='$section'}" -Encoding ascii
Copy-Item "$PSScriptRoot/DogJumpDriver.lua" "$session/appdata/RegularDriver.lua"
$meta.status = 'dog-prepared'
$meta | ConvertTo-Json -Depth 8 | Set-Content "$session/session.json"
if ($PrepareOnly) { Write-Output $session; return }
$game = $null
try {
    $game = Start-Process $engine -ArgumentList $meta.arguments -WorkingDirectory $runtime.FullName -PassThru
    $meta.status = 'dog-running'
    $meta | Add-Member gamePid $game.Id
    $meta | ConvertTo-Json -Depth 8 | Set-Content "$session/session.json"
    Write-Output "START dog case=$Case session=$session"
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while (!$game.WaitForExit(2000)) { if ((Get-Date) -gt $deadline) { throw 'Dog validation timed out' } }
    $logs = @(Get-ChildItem "$session/appdata/logs" -Filter '*.log')
    if ($logs.Count -ne 1) { throw 'Expected one log' }
    $log = [IO.File]::ReadAllText($logs[0].FullName)
    Assert-DogJumpLog $log $Case $game.ExitCode $Configuration
    $meta.status = 'dog-completed'
    Write-Output "COMPLETE dog case=$Case session=$session"
} catch {
    $meta.status = 'dog-failed'
    $meta | Add-Member failure $_.Exception.Message
    throw
} finally {
    if ($game -and !$game.HasExited) { Stop-Process -Id $game.Id; $game.WaitForExit() }
    if ($game) { $meta | Add-Member gameExitCode $game.ExitCode }
    $meta | ConvertTo-Json -Depth 8 | Set-Content "$session/session.json"
}
