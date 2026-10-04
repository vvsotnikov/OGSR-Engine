param(
    [Parameter(Mandatory)][string]$InstallRoot,
    [ValidatePattern('^bin_[a-zA-Z0-9_]+$')][string]$Package = 'bin_whole_lifecycle',
    [ValidateSet('distance', 'whole-map')][string]$Mode = 'distance',
    [ValidatePattern('^[a-zA-Z0-9_-]+$')][string]$SaveName = 'bar_center',
    [string]$SeedAppData = 'seeds/bar-2026-10-03'
)
$ErrorActionPreference = 'Stop'
$InstallRoot = (Resolve-Path $InstallRoot).Path
$repo = (Resolve-Path "$PSScriptRoot/../../../..").Path
$engine = Join-Path $InstallRoot "$Package/xrEngine.exe"
$seed = Join-Path $InstallRoot $SeedAppData
foreach ($required in @($engine, "$seed/savedgames/$SaveName.sav", "$InstallRoot/fsgame.ltx")) {
    if (!(Test-Path -LiteralPath $required)) { throw "Missing: $required" }
}
if (Get-Process xrEngine -ErrorAction SilentlyContinue) {
    throw 'Close the existing game before starting an isolated validation session.'
}
$id = (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss-fff') + '-' + $Mode
$session = New-Item -ItemType Directory (Join-Path $InstallRoot "captures/$id")
$appdata = New-Item -ItemType Directory "$($session.FullName)/appdata"
New-Item -ItemType Directory "$($appdata.FullName)/savedgames" | Out-Null
Copy-Item -Path "$seed/user*.ltx" -Destination $appdata.FullName
# Remove the load-screen key gate in this session only. Otherwise a timed
# unattended capture can record the waiting screen instead of gameplay.
Add-Content -LiteralPath "$($appdata.FullName)/user_ogsr.ltx" -Value "`nkeypress_on_start off" -Encoding ascii
Get-ChildItem -LiteralPath "$seed/savedgames" -File | Where-Object { $_.BaseName -eq $SaveName } |
    Copy-Item -Destination "$($appdata.FullName)/savedgames"
$fs = @(Get-Content -LiteralPath "$InstallRoot/fsgame.ltx")
$appRootLines = @(0..($fs.Count - 1) | Where-Object { $fs[$_] -match '^\s*\$app_data_root\$\s*=' })
if ($appRootLines.Count -ne 1) { throw 'Expected one app_data_root entry in fsgame.ltx' }
$fs[$appRootLines[0]] = '$app_data_root$ = true| false| $fs_root$| captures\' + $id + '\appdata\'
$fsPath = "$($session.FullName)/fsgame.ltx"
$fs | Set-Content -LiteralPath $fsPath -Encoding ascii
# X-Ray's legacy -fsltx parser does not support quoting or spaces. Use a
# space-free path relative to InstallRoot even when InstallRoot has spaces.
$argsText = '-fsltx captures\' + $id + '\fsgame.ltx'
if ($Mode -eq 'whole-map') { $argsText += ' -alife_whole_map' }
$argsText += " -start server($SaveName/single/alife/load) client(localhost)"
$metadata = [ordered]@{
    package = $Package; session = $id; mode = $Mode
    seedSave = "$seed/savedgames/$SaveName.sav"
    seedSha256 = (Get-FileHash "$seed/savedgames/$SaveName.sav").Hash
    engineSha256 = (Get-FileHash $engine).Hash
    sourceCommitAtLaunch = (& git -C $repo rev-parse HEAD)
    sourceDirtyAtLaunch = [bool](& git -C $repo status --porcelain)
    arguments = $argsText; status = 'prepared'
}
$metadata | ConvertTo-Json -Depth 6 | Set-Content "$($session.FullName)/session.json" -Encoding utf8
Write-Output $session.FullName
