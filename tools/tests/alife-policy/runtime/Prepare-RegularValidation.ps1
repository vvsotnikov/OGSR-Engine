param(
    [Parameter(Mandatory)][string]$BaselineRoot,
    [Parameter(Mandatory)][string]$InstallRoot,
    [ValidatePattern('^bin_[a-zA-Z0-9_]+$')][string]$Package = 'bin_whole_lifecycle'
)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $InstallRoot) { throw 'Use a new validation directory; existing data will not be overwritten' }
$sourcePackage = Join-Path $BaselineRoot $Package
. "$PSScriptRoot/ValidationPackage.ps1"
$build = Read-ValidationPackage "$sourcePackage/xrEngine.exe"
if ($build.sourcePatch) { throw 'Expected an unpatched package (build.json has sourcePatch)' }
New-Item -ItemType Directory $InstallRoot | Out-Null
# Read-only game archives share storage. Loose resources/scripts are private copies.
foreach ($archive in Get-ChildItem $BaselineRoot -File -Filter 'gamedata.db*') {
    New-Item -ItemType HardLink -Path (Join-Path $InstallRoot $archive.Name) -Target $archive.FullName | Out-Null
}
Copy-Item "$BaselineRoot/gamedata" -Destination $InstallRoot -Recurse
Copy-Item "$BaselineRoot/fsgame.ltx" "$InstallRoot/fsgame.ltx"
New-Item -ItemType Directory "$InstallRoot/seeds" | Out-Null
Copy-Item "$BaselineRoot/seeds/bar-2026-10-03" "$InstallRoot/seeds" -Recurse
Copy-Item $sourcePackage "$InstallRoot/$Package" -Recurse
# Preserve the original script's byte encoding; the bootstrap itself is ASCII.
$bootstrap = [IO.File]::ReadAllText("$PSScriptRoot/RegularBootstrap.lua")
[IO.File]::AppendAllText("$InstallRoot/gamedata/scripts/_g.script", "`n"+$bootstrap, [Text.Encoding]::ASCII)
@{sourceRoot=$BaselineRoot; sourceScriptSha256=(Get-FileHash "$BaselineRoot/gamedata/scripts/_g.script").Hash;
  engineSha256=$build.sha256; bootstrapSha256=(Get-FileHash "$PSScriptRoot/RegularBootstrap.lua").Hash} |
    ConvertTo-Json | Set-Content "$InstallRoot/setup.json" -Encoding utf8
