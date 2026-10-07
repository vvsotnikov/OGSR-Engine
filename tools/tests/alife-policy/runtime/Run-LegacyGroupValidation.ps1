param(
    [Parameter(Mandatory)][string]$InstallRoot,
    [Parameter(Mandatory)][ValidatePattern('^bin_[a-zA-Z0-9_]+$')][string]$Package,
    [Parameter(Mandatory)][string]$SeedAppData,
    [ValidatePattern('^[a-zA-Z0-9_-]+$')][string]$SaveName = 'legacy_group_fixture',
    [ValidateSet('setup','policy','verify','control','roundtrip','ownership')][string]$Stage = 'policy',
    [ValidateSet('distance','whole-map')][string]$Mode = 'whole-map',
    [ValidateSet('Release','Debug')][string]$Configuration = 'Debug',
    [ValidateRange(0,2147483647)][int]$Node = 34548,
    [ValidateRange(0,65534)][int]$Graph = 1233,
    [switch]$PrepareOnly
)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/ValidationPackage.ps1"
. "$PSScriptRoot/ValidationLog.ps1"
. "$PSScriptRoot/PolicyMessages.ps1"
if ($Stage -eq 'setup' -and $Mode -ne 'distance') { throw 'Create fixtures in distance mode, then load in a fresh process' }
if ($Stage -in @('policy','verify','roundtrip','ownership') -and $Mode -ne 'whole-map') { throw 'Use control to exercise inherited distance behavior' }
$InstallRoot=(Resolve-Path -LiteralPath $InstallRoot).Path
$engine=Join-Path $InstallRoot "$Package/xrEngine.exe"
$build=Read-ValidationPackage -Engine $engine -Configuration $Configuration
$session=& "$PSScriptRoot/Prepare-Session.ps1" -InstallRoot $InstallRoot -Package $Package -Mode $Mode -SeedAppData $SeedAppData -SaveName $SaveName
$meta=Get-Content "$session/session.json" -Raw | ConvertFrom-Json
$meta | Add-Member build $build
$meta | Add-Member stage $Stage
$runtime=New-Item -ItemType Directory "$session/runtime"
Copy-Item "$InstallRoot/gamedata" "$runtime/gamedata" -Recurse
Get-ChildItem $InstallRoot -Filter 'gamedata.db*' -File | ForEach-Object {
    New-Item -ItemType HardLink -Path "$runtime/$($_.Name)" -Target $_.FullName | Out-Null
}
$config="$runtime/gamedata/config/misc/items.ltx"
if ((Get-Content $config -Raw).Contains('[validation_flesh]')) { throw 'Legacy fixture sections already exist' }
# Immunities isolate ownership tests from incidental combat; kill() still
# exercises real death. These sections never change the user's game data.
@'

[validation_online_group]
class = ON_OFF_G
[validation_flesh]:flesh_weak
immunities_sect = validation_flesh_immunities
[validation_flesh_immunities]
burn_immunity = 0
strike_immunity = 0
shock_immunity = 0
wound_immunity = 0
radiation_immunity = 0
telepatic_immunity = 0
chemical_burn_immunity = 0
explosion_immunity = 0
fire_wound_immunity = 0
[validation_flesh_group]:validation_flesh
class = AI_FLE_G
monster_section = validation_flesh
'@ | Add-Content -LiteralPath $config -Encoding ascii
$fs=@(Get-Content "$session/fsgame.ltx")
$indices=@(0..($fs.Count-1) | Where-Object { $fs[$_] -match '^\s*\$app_data_root\$\s*=' })
if ($indices.Count -ne 1) { throw 'Expected one appdata root' }
$fs[$indices[0]]='$app_data_root$ = true| false| '+("$session/appdata/" -replace '/', '\')
$fs | Set-Content "$session/fsgame.ltx" -Encoding ascii
$meta.arguments='-fsltx ..\fsgame.ltx'+" -start server($SaveName/single/alife/load) client(localhost)"
if ($Mode -eq 'whole-map') { $meta.arguments+=' -alife_whole_map' }
Set-Content "$session/appdata/regular-config.lua" "return {stage='$Stage',mode='$Mode',node=$Node,graph=$Graph}" -Encoding ascii
Copy-Item "$PSScriptRoot/LegacyGroupDriver.lua" "$session/appdata/RegularDriver.lua"
Copy-Item "$PSScriptRoot/LegacyGroupFixture.lua" "$session/appdata/LegacyGroupFixture.lua"
if ($Stage -ne 'setup') { Copy-Item (Join-Path $InstallRoot "$SeedAppData/legacy-ids.lua") "$session/appdata/legacy-ids.lua" }
$meta.status='legacy-prepared'
$meta | ConvertTo-Json -Depth 8 | Set-Content "$session/session.json"
if ($PrepareOnly) { Write-Output $session;return }
$game=$null
try {
    $game=Start-Process $engine -ArgumentList $meta.arguments -WorkingDirectory $runtime.FullName -PassThru
    $meta.status='legacy-running';$meta | Add-Member gamePid $game.Id
    $meta | ConvertTo-Json -Depth 8 | Set-Content "$session/session.json"
    Write-Output "START legacy stage=$Stage mode=$Mode session=$session"
    $deadline=(Get-Date).AddSeconds(360)
    while (!$game.WaitForExit(2000)) { if ((Get-Date) -gt $deadline) { throw 'Legacy validation timed out' } }
    $logs=@(Get-ChildItem "$session/appdata/logs" -Filter '*.log')
    if ($logs.Count -ne 1) { throw 'Expected one log' }
    $log=[IO.File]::ReadAllText($logs[0].FullName)
    Assert-ValidationLogHealthy $log
    if ($Configuration -eq 'Debug' -and $log -notmatch 'Debug assertions: enabled') { throw 'Full Debug assertions missing' }
    $loads=if ($Stage -eq 'roundtrip') {5} else {1}
    Assert-PolicyMessages $log $Mode $loads $true
    if ($game.ExitCode -ne 0 -or $log -match '\[legacy policy\] FAILED' -or $log -notmatch "\[legacy policy\] complete stage=$Stage") { throw 'Legacy validation evidence incomplete' }
    if ($Stage -eq 'policy') {
        $phases=@([regex]::Matches($log,'\[legacy policy\] phase=(\d+) ') | ForEach-Object { $_.Groups[1].Value })
        if (($phases -join ',') -ne '1,2,3,4,5,6,7,8,9,10,11') { throw 'Legacy phases incomplete' }
    }
    if ($Stage -eq 'roundtrip') {
        $phases=@([regex]::Matches($log,'\[legacy trip\] phase=(\d+) ') | ForEach-Object { $_.Groups[1].Value })
        if (($phases -join ',') -ne '1,2,3,4,5') { throw 'Legacy roundtrip phases incomplete' }
    }
    $meta.status='legacy-completed'
    Write-Output "COMPLETE legacy session=$session"
} catch {
    $meta.status='legacy-failed';$meta | Add-Member failure $_.Exception.Message;throw
} finally {
    if ($game -and !$game.HasExited) { Stop-Process -Id $game.Id; $game.WaitForExit() }
    if ($game) { $meta | Add-Member gameExitCode $game.ExitCode -Force }
    $meta | ConvertTo-Json -Depth 8 | Set-Content "$session/session.json"
}
