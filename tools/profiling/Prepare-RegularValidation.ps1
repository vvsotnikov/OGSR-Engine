param(
    [string]$BaselineRoot = 'D:/Games/OGSR-Baseline',
    [string]$InstallRoot = 'D:/Games/OGSR-Regular-Validation'
)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $InstallRoot) { throw 'Use a new validation directory; existing data will not be overwritten' }
$package = Join-Path $BaselineRoot 'bin_regular'
$build = Get-Content -Raw "$package/build.json" | ConvertFrom-Json
if ($build.tracyEnabled -ne $false -or $build.sourcePatch) { throw 'Expected a clean non-Tracy Release package' }
New-Item -ItemType Directory $InstallRoot | Out-Null
# Read-only game archives share storage. Loose resources/scripts are private copies.
foreach ($archive in Get-ChildItem $BaselineRoot -File -Filter 'gamedata.db*') {
    New-Item -ItemType HardLink -Path (Join-Path $InstallRoot $archive.Name) -Target $archive.FullName | Out-Null
}
Copy-Item "$BaselineRoot/gamedata" -Destination $InstallRoot -Recurse
Copy-Item "$BaselineRoot/fsgame-profiler.ltx" "$InstallRoot/fsgame-profiler.ltx"
New-Item -ItemType Directory "$InstallRoot/seeds" | Out-Null
Copy-Item "$BaselineRoot/seeds/bar-2026-10-03" "$InstallRoot/seeds" -Recurse
Copy-Item $package "$InstallRoot/bin_experiment" -Recurse
# Preserve the original script's byte encoding; the bootstrap itself is ASCII.
$bootstrap = [IO.File]::ReadAllText("$PSScriptRoot/RegularBootstrap.lua")
[IO.File]::AppendAllText("$InstallRoot/gamedata/scripts/_g.script", "`n"+$bootstrap, [Text.Encoding]::ASCII)
@{sourceRoot=$BaselineRoot; sourceScriptSha256=(Get-FileHash "$BaselineRoot/gamedata/scripts/_g.script").Hash;
  engineSha256=(Get-FileHash "$package/xrEngine.exe").Hash; bootstrapSha256=(Get-FileHash "$PSScriptRoot/RegularBootstrap.lua").Hash} |
    ConvertTo-Json | Set-Content "$InstallRoot/setup.json" -Encoding utf8
