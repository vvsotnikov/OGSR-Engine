param(
    [Parameter(Mandatory)][string]$InstallRoot,
    [Parameter(Mandatory)][ValidatePattern('^bin_[a-zA-Z0-9_]+$')][string]$Package,
    [Parameter(Mandatory)][string]$SeedAppData,
    [string]$SaveName = 'group_validation',
    [ValidateSet('distance','whole-map')][string]$Mode = 'distance',
    [ValidateRange(0,65534)][int]$GroupId = 22016,
    [ValidateRange(0,65534)][int]$MemberId = 22017,
    [switch]$PrepareOnly
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/ValidationPackage.ps1"
. "$PSScriptRoot/ValidationLog.ps1"
. "$PSScriptRoot/PolicyMessages.ps1"
$InstallRoot = (Resolve-Path $InstallRoot).Path
$engine = Join-Path $InstallRoot "$Package/xrEngine.exe"
$build = Read-ValidationPackage $engine
$session = & "$PSScriptRoot/Prepare-Session.ps1" -InstallRoot $InstallRoot -Package $Package -Mode $Mode -SeedAppData $SeedAppData -SaveName $SaveName
$meta = Get-Content "$session/session.json" -Raw | ConvertFrom-Json
$meta | Add-Member build $build
$meta | Add-Member groupId $GroupId
$meta | Add-Member memberId $MemberId
# The saved fixture uses this server-only class section. Isolate all loose
# configuration while keeping archive virtual paths unchanged.
$runtime = New-Item -ItemType Directory "$session/runtime"
Copy-Item "$InstallRoot/gamedata" "$runtime/gamedata" -Recurse
Get-ChildItem $InstallRoot -Filter 'gamedata.db*' -File | ForEach-Object {
    New-Item -ItemType HardLink -Path "$runtime/$($_.Name)" -Target $_.FullName | Out-Null
}
$config = "$runtime/gamedata/config/misc/items.ltx"
if ((Get-Content $config -Raw).Contains('[validation_online_group]')) { throw 'Group fixture section already exists' }
Add-Content $config "`n[validation_online_group]`nclass = ON_OFF_G`n" -Encoding ascii
$fs = @(Get-Content "$session/fsgame.ltx")
$lines = @(0..($fs.Count-1) | Where-Object { $fs[$_] -match '^\s*\$app_data_root\$\s*=' })
if ($lines.Count -ne 1) { throw 'Expected one appdata root' }
$fs[$lines[0]] = '$app_data_root$ = true| false| ' + ("$session/appdata/" -replace '/', '\')
$fs | Set-Content "$session/fsgame.ltx" -Encoding ascii
# Resolve from the private runtime directory, including installations with spaces.
$meta.arguments = '-fsltx ..\fsgame.ltx' + " -start server($SaveName/single/alife/load) client(localhost)"
if ($Mode -eq 'whole-map') { $meta.arguments += ' -alife_whole_map' }
Set-Content "$session/appdata/regular-config.lua" "return {mode='$Mode',group=$GroupId,member=$MemberId}" -Encoding ascii
Copy-Item "$PSScriptRoot/GroupDriver.lua" "$session/appdata/RegularDriver.lua"
$meta.status = 'group-prepared'
$meta | ConvertTo-Json -Depth 8 | Set-Content "$session/session.json"
if ($PrepareOnly) { Write-Output $session; return }
$game = $null
try {
    $game = Start-Process $engine -ArgumentList $meta.arguments -WorkingDirectory $runtime.FullName -PassThru
    $meta.status = 'group-running'
    $meta | Add-Member gamePid $game.Id
    $meta | ConvertTo-Json -Depth 8 | Set-Content "$session/session.json"
    Write-Output "START group mode=$Mode session=$session"
    $deadline = (Get-Date).AddSeconds(240)
    while (!$game.WaitForExit(2000)) { if ((Get-Date) -gt $deadline) { throw 'Group validation timed out' } }
    $logs = @(Get-ChildItem "$session/appdata/logs" -Filter '*.log')
    if ($logs.Count -ne 1) { throw 'Expected one log' }
    $log = [IO.File]::ReadAllText($logs[0].FullName)
    Assert-ValidationLogHealthy $log
    Assert-PolicyMessages $log $Mode 1 $true
    $phases = @([regex]::Matches($log, '\[group policy\] phase=(\d)') | ForEach-Object { $_.Groups[1].Value })
    if ($game.ExitCode -ne 0 -or ($phases -join ',') -ne '1,2,3,4,5,6,7,8' -or $log -match '\[group policy\] FAILED' -or
        $log -notmatch '\[group policy\] complete member_dead=true (group_empty|group_removed)=true') { throw 'Group policy evidence incomplete' }
    $meta.status = 'group-completed'
    Write-Output "COMPLETE group mode=$Mode session=$session"
} catch {
    $meta.status = 'group-failed'
    $meta | Add-Member failure $_.Exception.Message
    throw
} finally {
    if ($game -and !$game.HasExited) { Stop-Process -Id $game.Id; $game.WaitForExit() }
    if ($game) { $meta | Add-Member gameExitCode $game.ExitCode -Force }
    $meta | ConvertTo-Json -Depth 8 | Set-Content "$session/session.json"
}
