param(
    [Parameter(Mandatory)][string]$InstallRoot,
    [Parameter(Mandatory)][ValidatePattern('^bin_[a-zA-Z0-9_]+$')][string]$Package,
    [ValidateSet('Debug','Release')][string]$Configuration = 'Debug',
    [ValidateSet('whole-map','distance')][string]$Mode = 'whole-map',
    [switch]$PrepareOnly
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/ValidationPackage.ps1"
. "$PSScriptRoot/ValidationLog.ps1"
. "$PSScriptRoot/PolicyMessages.ps1"
$InstallRoot = (Resolve-Path -LiteralPath $InstallRoot).Path
$engine = Join-Path $InstallRoot "$Package/xrEngine.exe"
$build = Read-ValidationPackage $engine -Configuration $Configuration
if (!(Get-Content "$InstallRoot/gamedata/scripts/_g.script" -Raw).Contains('regular-config.lua')) {
    throw 'Use an isolated installation prepared by Prepare-RegularValidation.ps1'
}
$session = & "$PSScriptRoot/Prepare-Session.ps1" -InstallRoot $InstallRoot -Package $Package -Mode $Mode
$meta = Get-Content "$session/session.json" -Raw | ConvertFrom-Json
$meta | Add-Member build $build
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
    $deadline = (Get-Date).AddSeconds(300)
    while (!$game.WaitForExit(2000)) { if ((Get-Date) -gt $deadline) { throw 'Physics reload timed out' } }
    $logs = @(Get-ChildItem "$session/appdata/logs" -Filter '*.log')
    if ($logs.Count -ne 1) { throw 'Expected one engine log' }
    $log = [IO.File]::ReadAllText($logs[0].FullName)
    Assert-ValidationLogHealthy $log
    Assert-PolicyMessages $log $Mode 3 $false
    if ($game.ExitCode -ne 0 -or $log -match '\[physics reload\] FAILED' -or
        $log -notmatch '\[physics reload\] saved_world_loaded' -or $log -notmatch '\[physics reload\] complete' -or
        $log -notmatch 'Game physics_reload\.sav is successfully saved' -or
        !(Test-Path "$session/appdata/savedgames/physics_reload.sav")) { throw 'Physics reload scenario failed' }
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
