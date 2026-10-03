param(
    [Parameter(Mandatory)][string]$InstallRoot,
    [Parameter(Mandatory)][string]$ToolRoot,
    [ValidatePattern('^bin_[a-zA-Z0-9_]+$')][string]$Package = 'bin_whole_lifecycle',
    [string]$SaveName = 'bar_center'
)
$ErrorActionPreference = 'Stop'
$session = & "$PSScriptRoot/Capture-Session.ps1" -InstallRoot $InstallRoot -ToolRoot $ToolRoot `
    -Package $Package -Mode whole-map -SeedAppData 'seeds/bar-2026-10-03' -SaveName $SaveName -PrepareOnly
$engine = Join-Path $InstallRoot "$Package/xrEngine.exe"
$path = Join-Path $session 'session.json'
$meta = Get-Content -Raw $path | ConvertFrom-Json
$meta.arguments = $meta.arguments.Replace(' -alife_metrics', '')
$meta.engineSha256 = (Get-FileHash $engine).Hash
$meta.build = Get-Content -Raw "$InstallRoot/$Package/build.json" | ConvertFrom-Json
$meta.status = 'manual-regular-running'
$game = Start-Process $engine -ArgumentList $meta.arguments -WorkingDirectory $InstallRoot -PassThru
$meta | Add-Member gamePid $game.Id
$meta | ConvertTo-Json -Depth 8 | Set-Content $path -Encoding utf8
Write-Output "Regular whole-map build launched. Private saves/logs: $session"
