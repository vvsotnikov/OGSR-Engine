param()
$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('ogsr-package-test-' + [guid]::NewGuid())
$seed = "$root/seeds/test"
New-Item -ItemType Directory -Path "$root/bin_selected", "$root/tools/bin", "$seed/savedgames" | Out-Null
Set-Content "$root/bin_selected/xrEngine.exe" 'fixture'
@{tracyEnabled=$false;configuration='Release'} | ConvertTo-Json | Set-Content "$root/bin_selected/build.json"
Set-Content "$root/tools/bin/tracy-capture.exe" 'fixture'
Set-Content "$seed/user_ogsr.ltx" 'fixture'
Set-Content "$seed/savedgames/test.sav" 'fixture'
Set-Content "$root/fsgame-profiler.ltx" '$app_data_root$ = unused'
$session = & "$PSScriptRoot/Capture-Session.ps1" -InstallRoot $root -ToolRoot "$root/tools" -Package bin_selected -SeedAppData seeds/test -SaveName test -PrepareOnly
$meta = Get-Content -Raw "$session/session.json" | ConvertFrom-Json
if ($meta.package -ne 'bin_selected' -or $meta.engineSha256 -ne (Get-FileHash "$root/bin_selected/xrEngine.exe").Hash) { throw 'Wrong package recorded' }
if (Test-Path "$root/bin_experiment") { throw 'Fixture unexpectedly has historical package' }
$rejected = $false
try { & "$PSScriptRoot/Capture-Session.ps1" -InstallRoot $root -ToolRoot "$root/tools" -Package bin_selected -SeedAppData seeds/test -SaveName test | Out-Null }
catch { if ($_.Exception.Message -notlike '*Tracy-enabled*') { throw }; $rejected=$true }
if (!$rejected) { throw 'Non-Tracy package accepted for capture' }
foreach ($option in @('CompactQueue','ActivationQueue','SavePending')) {
    $arguments = @{InstallRoot=$root;ToolRoot="$root/tools"}; $arguments[$option]=$true
    $rejected=$false
    try { & "$PSScriptRoot/Run-RegularValidation.ps1" @arguments | Out-Null }
    catch { if ($_.Exception.Message -notlike '*historical*') { throw }; $rejected=$true }
    if (!$rejected) { throw "Current package accepted $option" }
}
Write-Output 'Package selection, metadata, trace compatibility and obsolete-switch checks passed'
