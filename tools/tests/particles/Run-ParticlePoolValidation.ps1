param(
    [Parameter(Mandatory)][string]$InstallRoot,
    [Parameter(Mandatory)][ValidatePattern('^bin_[a-zA-Z0-9_]+$')][string]$Package,
    [string]$SeedAppData = 'seeds/bar-2026-10-03',
    [ValidatePattern('^[a-zA-Z0-9_-]+$')][string]$SaveName = 'bar_center',
    [switch]$PrepareOnly
)
$ErrorActionPreference='Stop'
$runtime="$PSScriptRoot/../alife-policy/runtime"
. "$runtime/ValidationLog.ps1"
$InstallRoot=(Resolve-Path -LiteralPath $InstallRoot).Path
$engine=Join-Path $InstallRoot "$Package/xrEngine.exe"
$build=Get-Content (Join-Path $InstallRoot "$Package/build.json") -Raw | ConvertFrom-Json
if ($build.configuration -cne 'Debug' -or $build.tracyEnabled -isnot [bool] -or $build.tracyEnabled -or
    $build.sha256 -ine (Get-FileHash $engine).Hash) { throw 'Expected a matching full-Debug package manifest' }
if (!(Get-Content "$InstallRoot/gamedata/scripts/_g.script" -Raw).Contains('regular-config.lua')) {
    throw 'Use an isolated installation prepared by Prepare-RegularValidation.ps1'
}
$session=& "$runtime/Prepare-Session.ps1" -InstallRoot $InstallRoot -Package $Package -Mode whole-map -SeedAppData $SeedAppData -SaveName $SaveName
$meta=Get-Content "$session/session.json" -Raw | ConvertFrom-Json
$meta | Add-Member build $build
Copy-Item "$PSScriptRoot/ParticlePoolDriver.lua" "$session/appdata/RegularDriver.lua"
Set-Content "$session/appdata/regular-config.lua" 'return {}' -Encoding ascii
$meta.status='particle-prepared';$meta | ConvertTo-Json -Depth 8 | Set-Content "$session/session.json"
if ($PrepareOnly) { Write-Output $session;return }
$game=$null
try {
    $game=Start-Process $engine -ArgumentList $meta.arguments -WorkingDirectory $InstallRoot -PassThru
    $meta.status='particle-running';$meta | Add-Member gamePid $game.Id
    $meta | ConvertTo-Json -Depth 8 | Set-Content "$session/session.json"
    Write-Output "START particle session=$session"
    $deadline=(Get-Date).AddSeconds(360)
    while (!$game.WaitForExit(2000)) { if ((Get-Date) -gt $deadline) { throw 'Particle validation timed out' } }
    $logs=@(Get-ChildItem "$session/appdata/logs" -Filter '*.log')
    if ($logs.Count -ne 1) { throw 'Expected one engine log' }
    $log=[IO.File]::ReadAllText($logs[0].FullName)
    Assert-ValidationLogHealthy $log
    $phases=@([regex]::Matches($log,'\[particle pool\] phase=(\d+) ') | ForEach-Object { $_.Groups[1].Value })
    if ($game.ExitCode -ne 0 -or $log -notmatch 'Debug assertions: enabled' -or $log -match '\[particle pool\] FAILED' -or
        $log -notmatch '\[particle pool\] complete' -or ($phases -join ',') -ne '1,2,3,4,5') { throw 'Particle validation evidence incomplete' }
    $meta.status='particle-completed';Write-Output "COMPLETE particle session=$session"
} catch {
    $meta.status='particle-failed';$meta | Add-Member failure $_.Exception.Message;throw
} finally {
    if ($game -and !$game.HasExited) { Stop-Process -Id $game.Id;$game.WaitForExit() }
    if ($game) { $meta | Add-Member gameExitCode $game.ExitCode -Force }
    $meta | ConvertTo-Json -Depth 8 | Set-Content "$session/session.json"
}
