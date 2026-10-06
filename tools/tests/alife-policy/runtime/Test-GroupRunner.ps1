$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('ogsr group ' + [guid]::NewGuid())
function Get-Process { param($Name, $ErrorAction) }
function Start-Process { throw 'Fixture prevented process launch' }
try {
    New-Item -ItemType Directory "$root/bin_fixture", "$root/seed/savedgames", "$root/gamedata/config/misc" | Out-Null
    Set-Content "$root/bin_fixture/xrEngine.exe" 'fixture'
    $hash = (Get-FileHash "$root/bin_fixture/xrEngine.exe").Hash
    @{configuration='Release'; tracyEnabled=$false; sha256=$hash} | ConvertTo-Json | Set-Content "$root/bin_fixture/build.json"
    Set-Content "$root/seed/savedgames/group_validation.sav" 'saved membership'
    Set-Content "$root/seed/user_ogsr.ltx" 'keypress_on_start on'
    Set-Content "$root/fsgame.ltx" '$app_data_root$ = true| false| $fs_root$| original\'
    Set-Content "$root/gamedata/config/misc/items.ltx" '[original]'
    Set-Content "$root/gamedata.db0" 'archive'
    $original = (Get-FileHash "$root/gamedata/config/misc/items.ltx").Hash
    $common = @{InstallRoot=$root; Package='bin_fixture'; SeedAppData='seed'}
    foreach ($mode in @('distance','whole-map')) {
        $session = & "$PSScriptRoot/Run-GroupValidation.ps1" @common -Mode $mode -PrepareOnly
        $meta = Get-Content "$session/session.json" -Raw | ConvertFrom-Json
        if ($meta.status -ne 'group-prepared' -or $meta.PSObject.Properties['gamePid'] -or
            $meta.arguments -notlike '-fsltx ..\fsgame.ltx *' -or
            ($meta.arguments.Contains('-alife_whole_map') -ne ($mode -eq 'whole-map'))) { throw 'Invalid prepared metadata' }
        if (!(Get-Content "$session/runtime/gamedata/config/misc/items.ltx" -Raw).Contains('[validation_online_group]') -or
            (Get-FileHash "$root/gamedata/config/misc/items.ltx").Hash -ne $original) { throw 'Configuration isolation failed' }
        if ((Get-Item "$session/runtime/gamedata.db0").LinkType -ne 'HardLink') { throw 'Archive was not linked' }
        if ((Get-FileHash "$session/appdata/RegularDriver.lua").Hash -ne (Get-FileHash "$PSScriptRoot/GroupDriver.lua").Hash -or
            !(Get-Content "$session/fsgame.ltx" -Raw).Contains(($session -replace '/', '\') + '\appdata\')) { throw 'Private runtime inputs incorrect' }
    }
    $before = @(Get-ChildItem "$root/captures" -Directory | ForEach-Object FullName)
    try { & "$PSScriptRoot/Run-GroupValidation.ps1" @common; throw 'Launch unexpectedly succeeded' }
    catch { if ($_.Exception.Message -ne 'Fixture prevented process launch') { throw } }
    $failed = @(Get-ChildItem "$root/captures" -Directory | Where-Object FullName -NotIn $before)
    $meta = Get-Content "$($failed[0].FullName)/session.json" -Raw | ConvertFrom-Json
    if ($failed.Count -ne 1 -or $meta.status -ne 'group-failed' -or $meta.failure -ne 'Fixture prevented process launch') { throw 'Lost launch failure' }
    function Start-Process {
        $process = [pscustomobject]@{Id=123; ExitCode=7; HasExited=$true}
        $process | Add-Member ScriptMethod WaitForExit { param($Timeout) return $true }
        return $process
    }
    $before = @(Get-ChildItem "$root/captures" -Directory | ForEach-Object FullName)
    try { & "$PSScriptRoot/Run-GroupValidation.ps1" @common | Out-Null; throw 'Missing evidence accepted' }
    catch { if ($_.Exception.Message -eq 'Missing evidence accepted') { throw } }
    $failed = @(Get-ChildItem "$root/captures" -Directory | Where-Object FullName -NotIn $before)
    $meta = Get-Content "$($failed[0].FullName)/session.json" -Raw | ConvertFrom-Json
    if ($failed.Count -ne 1 -or $meta.status -ne 'group-failed' -or $meta.gameExitCode -ne 7) { throw 'Lost failed process exit code' }
    Write-Output 'Group runner preparation and launch failure passed'
} finally {
    $resolved = [IO.Path]::GetFullPath($root)
    if (!$resolved.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
