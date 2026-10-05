$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('ogsr-runner-' + [guid]::NewGuid())
New-Item -ItemType Directory $root | Out-Null
$root = (Resolve-Path -LiteralPath $root).Path
# Only process discovery/creation is replaced. Session preparation, package
# validation, copying and serialization execute their actual implementations.
function Get-Process { param($Name, $ErrorAction) }
function Start-Process { throw 'PrepareOnly attempted to launch a process' }
try {
    $package = Join-Path $root 'bin_fixture'
    $seed = Join-Path $root 'seed'
    New-Item -ItemType Directory $package, "$seed/savedgames" | Out-Null
    Set-Content "$package/xrEngine.exe" 'fixture executable'
    Set-Content "$seed/savedgames/bar_center.sav" 'fixture save'
    Set-Content "$seed/user_ogsr.ltx" 'keypress_on_start on'
    Set-Content "$root/fsgame.ltx" '$app_data_root$ = true| false| $fs_root$| original\'
    $hash = (Get-FileHash "$package/xrEngine.exe").Hash
    @{configuration='Release'; tracyEnabled=$false; sha256=$hash} |
        ConvertTo-Json | Set-Content "$package/build.json"
    $seedHash = (Get-FileHash "$seed/savedgames/bar_center.sav").Hash
    $settingsHash = (Get-FileHash "$seed/user_ogsr.ltx").Hash
    $fsHash = (Get-FileHash "$root/fsgame.ltx").Hash
    foreach ($mode in @('distance', 'whole-map')) {
        $session = & "$PSScriptRoot/Run-RegularValidation.ps1" -InstallRoot $root -Package bin_fixture `
            -SeedAppData seed -Count 3 -BudgetMs 2 -DistanceControl -Mode $mode -PrepareOnly
        $meta = Get-Content -Raw "$session/session.json" | ConvertFrom-Json
        if ($meta.status -ne 'regular-prepared' -or $meta.PSObject.Properties['gamePid']) {
            throw 'Preparation claimed a running game'
        }
        if ($meta.package -ne 'bin_fixture' -or $meta.engineSha256 -ne $hash -or
            $meta.build.sha256 -ne $hash -or $meta.build.configuration -ne 'Release' -or
            $meta.build.tracyEnabled -isnot [bool] -or $meta.build.tracyEnabled) {
            throw 'Validated package metadata was not preserved'
        }
        if ($meta.extraRequested -ne 3 -or $meta.spawnBudgetMs -ne 2 -or !$meta.distanceControl -or
            $meta.mode -ne $mode -or ($meta.arguments.Contains('-alife_whole_map') -ne ($mode -eq 'whole-map'))) {
            throw 'Requested scenario was not preserved'
        }
        $config = Get-Content -Raw "$session/appdata/regular-config.lua"
        if (!$config.Contains("mode='$mode'") -or !$config.Contains('count=3, budget_ms=2') -or
            !$config.Contains('distance_control=true')) { throw 'Lua configuration does not match session' }
        if ((Get-FileHash "$session/appdata/savedgames/bar_center.sav").Hash -ne $seedHash -or
            (Get-FileHash "$session/appdata/RegularDriver.lua").Hash -ne (Get-FileHash "$PSScriptRoot/RegularDriver.lua").Hash) {
            throw 'Session inputs were not copied intact'
        }
        if (!(Get-Content -Raw "$session/fsgame.ltx").Contains("captures\$($meta.session)\appdata\")) {
            throw 'Session does not use private appdata'
        }
    }
    if ((Get-FileHash "$seed/user_ogsr.ltx").Hash -ne $settingsHash -or
        (Get-FileHash "$root/fsgame.ltx").Hash -ne $fsHash -or
        (Get-FileHash "$seed/savedgames/bar_center.sav").Hash -ne $seedHash) {
        throw 'Preparation modified original inputs'
    }
} finally {
    # Remove only this freshly created fixture, never a caller-supplied path.
    if ((Resolve-Path -LiteralPath $root).Path -ne $root -or
        (Split-Path -Leaf $root) -notmatch '^ogsr-runner-[0-9a-f-]{36}$') { throw 'Unexpected fixture path' }
    Remove-Item -LiteralPath $root -Recurse
}
