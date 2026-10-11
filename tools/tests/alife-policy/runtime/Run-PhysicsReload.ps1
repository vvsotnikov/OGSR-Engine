param(
    [Parameter(Mandatory)][string]$InstallRoot,
    [Parameter(Mandatory)][ValidatePattern('^bin_[a-zA-Z0-9_]+$')][string]$Package,
    [ValidateSet('Debug','Release')][string]$Configuration = 'Debug',
    [ValidateSet('whole-map','distance')][string]$Mode = 'whole-map',
    [string]$SeedAppData = 'seeds/bar-2026-10-03',
    [ValidatePattern('^[a-zA-Z0-9_-]+$')][string]$SaveName = 'bar_center',
    [ValidateRange(1, 86400)][int]$TimeoutSeconds = 300,
    [switch]$PrepareOnly
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/ValidationPackage.ps1"
. "$PSScriptRoot/ValidationLog.ps1"
. "$PSScriptRoot/PolicyMessages.ps1"
. "$PSScriptRoot/PhysicsReloadLog.ps1"
$InstallRoot = (Resolve-Path -LiteralPath $InstallRoot).Path
$engine = Join-Path $InstallRoot "$Package/xrEngine.exe"
$build = Read-ValidationPackage $engine -Configuration $Configuration
if (!(Get-Content "$InstallRoot/gamedata/scripts/_g.script" -Raw).Contains('regular-config.lua')) {
    throw 'Use an isolated installation prepared by Prepare-RegularValidation.ps1'
}
$session = & "$PSScriptRoot/Prepare-Session.ps1" -InstallRoot $InstallRoot -Package $Package -Mode $Mode -SeedAppData $SeedAppData -SaveName $SaveName
$meta = Get-Content "$session/session.json" -Raw | ConvertFrom-Json
$meta | Add-Member build $build
$meta | Add-Member timeoutSeconds $TimeoutSeconds
$meta.arguments += " -physics_reload_probe"
Copy-Item "$PSScriptRoot/PhysicsReloadDriver.lua" "$session/appdata/RegularDriver.lua"
Set-Content "$session/appdata/regular-config.lua" 'return {}' -Encoding ascii
$meta.status = 'physics-prepared'
$meta | ConvertTo-Json -Depth 8 | Set-Content "$session/session.json"
if ($PrepareOnly) { Write-Output $session; return }
$game = $null
try {
    $game = Start-Process $engine -ArgumentList $meta.arguments -WorkingDirectory $InstallRoot -PassThru
    $meta.status = 'physics-running'
    $meta | Add-Member gamePid $game.Id
    $meta | ConvertTo-Json -Depth 8 | Set-Content "$session/session.json"
    Write-Output "START physics session=$session"
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while (!$game.WaitForExit(2000)) { if ((Get-Date) -gt $deadline) { throw 'Physics reload timed out' } }
    $logs = @(Get-ChildItem "$session/appdata/logs" -Filter '*.log')
    if ($logs.Count -ne 1) { throw 'Expected one engine log' }
    $log = [IO.File]::ReadAllText($logs[0].FullName)
    Assert-PhysicsReloadLog $log $game.ExitCode $Mode
    if (!(Test-Path "$session/appdata/savedgames/physics_reload.sav")) { throw 'Missing physics reload save' }
    $meta.status = 'physics-completed'
    Write-Output "COMPLETE physics session=$session"
} catch {
    $meta.status = 'physics-failed'
    $meta | Add-Member failure $_.Exception.Message
    throw
} finally {
    if ($game -and !$game.HasExited) { Stop-Process -Id $game.Id; $game.WaitForExit() }
    if ($game) { $meta | Add-Member gameExitCode $game.ExitCode -Force }
    $meta | ConvertTo-Json -Depth 8 | Set-Content "$session/session.json"
}
