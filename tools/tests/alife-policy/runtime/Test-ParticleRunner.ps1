$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/ValidationLog.ps1"
. "$PSScriptRoot/ParticlePoolLog.ps1"
$evidence = @('Debug assertions: enabled', '[particle pool] reused-after-child-reset group=fixture') +
    @(1..5 | ForEach-Object { "[particle pool] phase=$_ map=fixture" }) + '[particle pool] complete'
Assert-ParticlePoolLog ($evidence -join "`n") 0
foreach ($missing in 0..7) {
    $incomplete = @(0..7 | Where-Object { $_ -ne $missing } | ForEach-Object { $evidence[$_] })
    $rejected = $false
    try { Assert-ParticlePoolLog ($incomplete -join "`n") 0 } catch { $rejected = $true }
    if (!$rejected) { throw "Accepted evidence missing line $missing" }
}
foreach ($bad in @(@{Log=($evidence -join "`n"); Exit=1},
    @{Log=(($evidence + '[particle pool] FAILED test') -join "`n"); Exit=0})) {
    $rejected = $false
    try { Assert-ParticlePoolLog $bad.Log $bad.Exit } catch { $rejected = $true }
    if (!$rejected) { throw 'Accepted failed runtime evidence' }
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('ogsr-particle-' + [guid]::NewGuid())
New-Item -ItemType Directory $root | Out-Null
$root = (Resolve-Path -LiteralPath $root).Path
function Get-Process { param($Name, $ErrorAction) }
function Start-Process { throw 'Fixture prevented process launch' }
try {
    New-Item -ItemType Directory "$root/bin_fixture", "$root/seed/savedgames", "$root/gamedata/scripts" | Out-Null
    Set-Content "$root/bin_fixture/xrEngine.exe" 'fixture executable'
    Set-Content "$root/seed/savedgames/bar_center.sav" 'fixture save'
    Set-Content "$root/seed/user_ogsr.ltx" 'keypress_on_start on'
    Set-Content "$root/fsgame.ltx" '$app_data_root$ = true| false| $fs_root$| original\'
    Set-Content "$root/gamedata/scripts/_g.script" 'regular-config.lua'
    $hash = (Get-FileHash "$root/bin_fixture/xrEngine.exe").Hash
    $manifest = @{configuration='Debug'; tracyEnabled=$false; sha256=$hash}
    $manifest | ConvertTo-Json | Set-Content "$root/bin_fixture/build.json"
    $originals = @('seed/savedgames/bar_center.sav', 'seed/user_ogsr.ltx', 'fsgame.ltx')
    $hashes = @($originals | ForEach-Object { (Get-FileHash "$root/$_").Hash })
    $runner = "$PSScriptRoot/Run-ParticlePoolValidation.ps1"
    $runArgs = @{InstallRoot=$root; Package='bin_fixture'; SeedAppData='seed'; TimeoutSeconds=900}
    $session = & $runner @runArgs -PrepareOnly
    $meta = Get-Content "$session/session.json" -Raw | ConvertFrom-Json
    if ($meta.status -ne 'particle-prepared' -or $meta.PSObject.Properties['gamePid'] -or
        $meta.timeoutSeconds -ne 900 -or $meta.build.configuration -ne 'Debug' -or
        $meta.engineSha256 -ne $hash -or !$meta.arguments.Contains('-alife_whole_map') -or !$meta.arguments.Contains('-particle_pool_probe')) {
        throw 'Prepared session metadata is incorrect'
    }
    if ((Get-FileHash "$session/appdata/RegularDriver.lua").Hash -ne
        (Get-FileHash "$PSScriptRoot/ParticlePoolDriver.lua").Hash -or
        !(Get-Content "$session/fsgame.ltx" -Raw).Contains("captures\$($meta.session)\appdata\")) {
        throw 'Session driver or private appdata is incorrect'
    }
    foreach ($invalid in @(@{configuration='Release'; tracyEnabled=$false; sha256=$hash},
        @{configuration='Debug'; tracyEnabled=$true; sha256=$hash},
        @{configuration='Debug'; tracyEnabled=$false; sha256='invalid'})) {
        $invalid | ConvertTo-Json | Set-Content "$root/bin_fixture/build.json"
        $rejected = $false
        try { & $runner @runArgs -PrepareOnly | Out-Null } catch {
            if ($_.Exception.Message -notin @('Validation requires a Debug package with tracyEnabled=false',
                'Validation package executable hash does not match build.json')) { throw }
            $rejected = $true
        }
        if (!$rejected) { throw 'Accepted invalid package manifest' }
    }
    $manifest | ConvertTo-Json | Set-Content "$root/bin_fixture/build.json"
    $rejected = $false
    try { & $runner @runArgs | Out-Null } catch {
        if ($_.Exception.Message -ne 'Fixture prevented process launch') { throw }
        $rejected = $true
    }
    if (!$rejected) { throw 'Launch failure did not propagate' }
    $failed = @(Get-ChildItem "$root/captures" -Directory | Where-Object FullName -ne $session)
    $meta = Get-Content "$($failed[0].FullName)/session.json" -Raw | ConvertFrom-Json
    if ($failed.Count -ne 1 -or $meta.status -ne 'particle-failed' -or
        $meta.failure -ne 'Fixture prevented process launch') { throw 'Launch failure was not recorded' }
    $after = @($originals | ForEach-Object { (Get-FileHash "$root/$_").Hash })
    if (($hashes -join ',') -ne ($after -join ',')) { throw 'Preparation modified original inputs' }
} finally {
    if ((Resolve-Path -LiteralPath $root).Path -ne $root -or
        (Split-Path -Leaf $root) -notmatch '^ogsr-particle-[0-9a-f-]{36}$') { throw 'Unexpected fixture path' }
    Remove-Item -LiteralPath $root -Recurse
}

