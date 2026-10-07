$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('ogsr legacy ' + [guid]::NewGuid())
function Get-Process { param($Name, $ErrorAction) }
function Start-Process { throw 'Unexpected game launch' }
try {
    New-Item -ItemType Directory "$root/bin_fixture", "$root/seed/savedgames", "$root/gamedata/config/misc" | Out-Null
    Set-Content "$root/bin_fixture/xrEngine.exe" 'fixture'
    $hash = (Get-FileHash "$root/bin_fixture/xrEngine.exe").Hash
    @{configuration='Debug'; tracyEnabled=$false; sha256=$hash} | ConvertTo-Json | Set-Content "$root/bin_fixture/build.json"
    Set-Content "$root/seed/savedgames/legacy_group_fixture.sav" 'fixture save'
    Set-Content "$root/seed/legacy-ids.lua" 'return {group=1,members={2,3,4,5}}'
    Set-Content "$root/seed/user_ogsr.ltx" 'keypress_on_start on'
    Set-Content "$root/fsgame.ltx" '$app_data_root$ = true| false| $fs_root$| original\'
    Set-Content "$root/gamedata/config/misc/items.ltx" '[original]'
    Set-Content "$root/gamedata.db0" 'archive'
    $original = (Get-FileHash "$root/gamedata/config/misc/items.ltx").Hash
    foreach ($stage in @('setup','policy','verify','control','roundtrip','ownership')) {
        $mode = if ($stage -eq 'setup') {'distance'} else {'whole-map'}
        $session = & "$PSScriptRoot/Run-LegacyGroupValidation.ps1" -InstallRoot $root -Package bin_fixture -SeedAppData seed -Stage $stage -Mode $mode -PrepareOnly
        $meta = Get-Content "$session/session.json" -Raw | ConvertFrom-Json
        if ($meta.status -ne 'legacy-prepared' -or $meta.stage -ne $stage -or $meta.PSObject.Properties['gamePid']) { throw 'Preparation claims runtime evidence' }
        if ((Get-FileHash "$root/gamedata/config/misc/items.ltx").Hash -ne $original -or
            !(Get-Content "$session/runtime/gamedata/config/misc/items.ltx" -Raw).Contains('class = AI_FLE_G')) { throw 'Fixture isolation failed' }
        if ((Get-Item "$session/runtime/gamedata.db0").LinkType -ne 'HardLink') { throw 'Archive was not linked' }
        if ((Test-Path "$session/appdata/legacy-ids.lua") -ne ($stage -ne 'setup')) { throw 'Wrong saved membership input' }
        foreach ($file in @('LegacyGroupFixture.lua','LegacyGroupDriver.lua')) {
            $copied = if ($file -eq 'LegacyGroupDriver.lua') {'RegularDriver.lua'} else {$file}
            if ((Get-FileHash "$session/appdata/$copied").Hash -ne (Get-FileHash "$PSScriptRoot/$file").Hash) { throw 'Driver mismatch' }
        }
    }
} finally {
    $resolved = [IO.Path]::GetFullPath($root)
    if (!$resolved.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
