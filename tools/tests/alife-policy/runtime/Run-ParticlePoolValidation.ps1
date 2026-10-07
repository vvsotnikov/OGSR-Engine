param(
    [Parameter(Mandatory)][string]$InstallRoot,
    [Parameter(Mandatory)][ValidatePattern('^bin_[a-zA-Z0-9_]+$')][string]$Package,
    [string]$SeedAppData = 'seeds/bar-2026-10-03',
    [ValidatePattern('^[a-zA-Z0-9_-]+$')][string]$SaveName = 'bar_center',
    [ValidateRange(1, 86400)][int]$TimeoutSeconds = 600,
    [switch]$PrepareOnly
)
$ErrorActionPreference = 'Stop'
$runtime = $PSScriptRoot
. "$runtime/ValidationLog.ps1"
. "$runtime/ParticlePoolLog.ps1"
$InstallRoot = (Resolve-Path -LiteralPath $InstallRoot).Path
$engine = Join-Path $InstallRoot "$Package/xrEngine.exe"
. "$runtime/ValidationPackage.ps1"
$build = Read-ValidationPackage -Engine $engine -Configuration Debug
if (!(Get-Content "$InstallRoot/gamedata/scripts/_g.script" -Raw).Contains('regular-config.lua')) {
    throw 'Use an isolated installation prepared by Prepare-RegularValidation.ps1'
}
$session = & "$runtime/Prepare-Session.ps1" -InstallRoot $InstallRoot -Package $Package -Mode whole-map -SeedAppData $SeedAppData -SaveName $SaveName
$meta = Get-Content "$session/session.json" -Raw | ConvertFrom-Json
$meta.arguments += " -particle_pool_probe"
$meta | Add-Member build $build
$meta | Add-Member timeoutSeconds $TimeoutSeconds
Copy-Item "$PSScriptRoot/ParticlePoolDriver.lua" "$session/appdata/RegularDriver.lua"
Set-Content "$session/appdata/regular-config.lua" 'return {}' -Encoding ascii
$meta.status = 'particle-prepared'
$meta | ConvertTo-Json -Depth 8 | Set-Content "$session/session.json"
if ($PrepareOnly) {
    Write-Output $session
    return
}
$game = $null
try {
    $game = Start-Process $engine -ArgumentList $meta.arguments -WorkingDirectory $InstallRoot -PassThru
    $meta.status = 'particle-running'
    $meta | Add-Member gamePid $game.Id
    $meta | ConvertTo-Json -Depth 8 | Set-Content "$session/session.json"
    Write-Output "START particle session=$session"
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while (!$game.WaitForExit(2000)) { if ((Get-Date) -gt $deadline) { throw 'Particle validation timed out' } }
    $logs = @(Get-ChildItem "$session/appdata/logs" -Filter '*.log')
    if ($logs.Count -ne 1) { throw 'Expected one engine log' }
    $log = [IO.File]::ReadAllText($logs[0].FullName)
    Assert-ParticlePoolLog $log $game.ExitCode
    $meta.status = 'particle-completed'
    Write-Output "COMPLETE particle session=$session"
} catch {
    $meta.status = 'particle-failed'
    $meta | Add-Member failure $_.Exception.Message
    throw
} finally {
    if ($game -and !$game.HasExited) {
        Stop-Process -Id $game.Id
        $game.WaitForExit()
    }
    if ($game) { $meta | Add-Member gameExitCode $game.ExitCode -Force }
    $meta | ConvertTo-Json -Depth 8 | Set-Content "$session/session.json"
}
