$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/ValidationLog.ps1"
. "$PSScriptRoot/PolicyMessages.ps1"
. "$PSScriptRoot/PhysicsReloadLog.ps1"
$evidence = @('* ALife policy: whole-map (EXPERIMENTAL);') * 3 + @(
    '[physics reload] saved_world_loaded',
    'Game physics_reload.sav is successfully saved',
    '[physics reload] partial_shell object=23 hidden=2 elements=1',
    '[physics reload] complete')
Assert-PhysicsReloadLog ($evidence -join "`n") 0 whole-map
foreach ($missing in 0..6) {
    $incomplete = @(0..6 | Where-Object { $_ -ne $missing } | ForEach-Object { $evidence[$_] })
    $rejected = $false
    try { Assert-PhysicsReloadLog ($incomplete -join "`n") 0 whole-map } catch { $rejected = $true }
    if (!$rejected) { throw "Accepted evidence missing line $missing" }
}
$valid = $evidence -join "`n"
foreach ($bad in @(
    @{Log=$valid; Exit=1},
    @{Log=$valid + "`n[physics reload] FAILED hidden_shell"; Exit=0},
    @{Log=$valid.Replace('hidden=2','hidden=0'); Exit=0},
    @{Log=$valid.Replace('elements=1','elements=0'); Exit=0},
    @{Log=('[physics reload] partial_shell object=23 hidden=2 elements=1' + "`n" + $valid.Replace('[physics reload] partial_shell object=23 hidden=2 elements=1','')); Exit=0})) {
    $rejected = $false
    try { Assert-PhysicsReloadLog $bad.Log $bad.Exit whole-map } catch { $rejected = $true }
    if (!$rejected) { throw 'Accepted failed runtime evidence' }
}
Assert-PhysicsReloadLog (($evidence | Select-Object -Skip 3) -join "`n") 0 distance

$root = Join-Path ([IO.Path]::GetTempPath()) ('ogsr-physics-' + [guid]::NewGuid())
New-Item -ItemType Directory $root | Out-Null
$root = (Resolve-Path -LiteralPath $root).Path
function Get-Process { param($Name, $ErrorAction) }
function Start-Process { throw 'Fixture prevented process launch' }
try {
    New-Item -ItemType Directory "$root/bin_fixture", "$root/seed/savedgames", "$root/gamedata/scripts" | Out-Null
    Set-Content "$root/bin_fixture/xrEngine.exe" 'fixture executable'
    Set-Content "$root/seed/savedgames/chosen_save.sav" 'fixture save'
    Set-Content "$root/seed/user_ogsr.ltx" 'keypress_on_start on'
    Set-Content "$root/fsgame.ltx" '$app_data_root$ = true| false| $fs_root$| original\'
    Set-Content "$root/gamedata/scripts/_g.script" 'regular-config.lua'
    $hash = (Get-FileHash "$root/bin_fixture/xrEngine.exe").Hash
    $manifest = @{configuration='Debug'; tracyEnabled=$false; sha256=$hash}
    $manifest | ConvertTo-Json | Set-Content "$root/bin_fixture/build.json"
    $originals = @('seed/savedgames/chosen_save.sav', 'seed/user_ogsr.ltx', 'fsgame.ltx')
    $hashes = @($originals | ForEach-Object { (Get-FileHash "$root/$_").Hash })
    $runner = "$PSScriptRoot/Run-PhysicsReload.ps1"
    $runArgs = @{InstallRoot=$root; Package='bin_fixture'; SeedAppData='seed'; SaveName='chosen_save'; TimeoutSeconds=900}
    $session = & $runner @runArgs -PrepareOnly
    $meta = Get-Content "$session/session.json" -Raw | ConvertFrom-Json
    if ($meta.status -ne 'physics-prepared' -or $meta.PSObject.Properties['gamePid'] -or
        $meta.timeoutSeconds -ne 900 -or $meta.build.configuration -ne 'Debug' -or
        $meta.engineSha256 -ne $hash -or !$meta.arguments.Contains('-alife_whole_map') -or !$meta.arguments.Contains('-physics_reload_probe')) {
        throw 'Prepared session metadata is incorrect'
    }
    if ((Get-FileHash "$session/appdata/RegularDriver.lua").Hash -ne
        (Get-FileHash "$PSScriptRoot/PhysicsReloadDriver.lua").Hash -or
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
    if ($failed.Count -ne 1 -or $meta.status -ne 'physics-failed' -or
        $meta.failure -ne 'Fixture prevented process launch') { throw 'Launch failure was not recorded' }
    $after = @($originals | ForEach-Object { (Get-FileHash "$root/$_").Hash })
    if (($hashes -join ',') -ne ($after -join ',')) { throw 'Preparation modified original inputs' }
} finally {
    if ((Resolve-Path -LiteralPath $root).Path -ne $root -or
        (Split-Path -Leaf $root) -notmatch '^ogsr-physics-[0-9a-f-]{36}$') { throw 'Unexpected fixture path' }
    Remove-Item -LiteralPath $root -Recurse
}

