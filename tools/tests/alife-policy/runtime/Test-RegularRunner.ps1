$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('ogsr-runner-' + [guid]::NewGuid())
New-Item -ItemType Directory $root | Out-Null
$root = (Resolve-Path -LiteralPath $root).Path
# Only process discovery/creation is replaced. Session preparation, package
# validation, copying and serialization execute their actual implementations.
function Get-Process { param($Name, $ErrorAction) }
function Start-Process { throw 'Fixture prevented process launch' }
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
    function Assert-Rejected([scriptblock]$Action, [string]$Expected) {
        try { & $Action | Out-Null } catch {
            if ($_.Exception.Message -ne $Expected) { throw }
            return
        }
        throw "Accepted invalid scenario: $Expected"
    }
    $runner = "$PSScriptRoot/Run-RegularValidation.ps1"
    $common = @{ InstallRoot=$root; Package='bin_fixture'; SeedAppData='seed'; PrepareOnly=$true }
    foreach ($extra in @(@{Count=1}, @{Eligibility=$true}, @{SaveSnapshot=$true}, @{VerifySession='unused'})) {
        Assert-Rejected { & $runner @common -Transitions @extra } 'Transition fixture must run by itself'
    }
    Assert-Rejected { & $runner @common -Mode distance -Eligibility } 'Eligibility fixture requires whole-map mode'

    $source = "$root/saved-evidence"
    New-Item -ItemType Directory "$source/appdata/logs" | Out-Null
    $sourceMeta = @{status='regular-completed'; extraRequested=3}
    $sourceMeta | ConvertTo-Json | Set-Content "$source/session.json"
    $sourceLines = '[regular spawn] index=1 id=101', '[regular spawn] index=2 id=205', '[regular spawn] index=3 id=309'
    $sourceLines | Set-Content "$source/appdata/logs/source.log"
    $session = & $runner @common -VerifySession $source
    $meta = Get-Content -Raw "$session/session.json" | ConvertFrom-Json
    $config = Get-Content -Raw "$session/appdata/regular-config.lua"
    if (($meta.verifyIds -join ',') -ne '101,205,309' -or !$config.Contains('verify_ids={101,205,309}') -or
        $meta.extraRequested -ne 0 -or $meta.status -ne 'regular-prepared') {
        throw 'Saved IDs did not reach both metadata and Lua configuration'
    }
    $sourceMeta.status='regular-failed'
    $sourceMeta | ConvertTo-Json | Set-Content "$source/session.json"
    Assert-Rejected { & $runner @common -VerifySession $source } 'Verify source session is incomplete'
    $sourceMeta.status='regular-completed'
    $sourceMeta | ConvertTo-Json | Set-Content "$source/session.json"
    foreach ($badLog in @('', ($sourceLines[0..1] -join "`n"), ($sourceLines[0],$sourceLines[1],$sourceLines[1] -join "`n"))) {
        Set-Content "$source/appdata/logs/source.log" $badLog -NoNewline
        Assert-Rejected { & $runner @common -VerifySession $source } 'Invalid saved population evidence'
    }
    $sourceLines | Set-Content "$source/appdata/logs/source.log"
    $sourceLines | Set-Content "$source/appdata/logs/second.log"
    Assert-Rejected { & $runner @common -VerifySession $source } 'Expected one source session log'

    $existing = @(Get-ChildItem "$root/captures" -Directory | ForEach-Object FullName)
    $rejected = $false
    try {
        & "$PSScriptRoot/Run-RegularValidation.ps1" -InstallRoot $root -Package bin_fixture -SeedAppData seed
    } catch {
        if ($_.Exception.Message -ne 'Fixture prevented process launch') { throw }
        $rejected = $true
    }
    if (!$rejected) { throw 'Launch failure did not propagate' }
    $failed = @(Get-ChildItem "$root/captures" -Directory | Where-Object { $_.FullName -notin $existing })
    if ($failed.Count -ne 1) { throw 'Expected one failed launch session' }
    $meta = Get-Content -Raw "$($failed[0].FullName)/session.json" | ConvertFrom-Json
    if ($meta.status -ne 'regular-failed' -or $meta.failure -ne 'Fixture prevented process launch' -or
        $meta.PSObject.Properties['gamePid']) { throw 'Launch failure was not recorded accurately' }
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
