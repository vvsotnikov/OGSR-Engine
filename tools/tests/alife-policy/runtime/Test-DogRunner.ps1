$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/ValidationLog.ps1"
. "$PSScriptRoot/DogJumpLog.ps1"
$log = @'
Debug assertions: enabled
[dog fixture] begin section=validation_jump_default
[dog fixture] spawned id=123 section=validation_jump_default
[dog fixture] spawned id=124 section=validation_jump_default
[dog fixture] spawned id=125 section=validation_jump_default
[dog jump] id=123 section=validation_jump_default attack=stand_attack_0 power=0.150000 impulse=30.000000
[dog fixture] complete
'@
Assert-DogJumpLog $log default 0
$override = $log.Replace('validation_jump_default','validation_jump_override').Replace('stand_attack_0 power=0.150000 impulse=30.000000','jump_right_0 power=0.370000 impulse=47.000000')
Assert-DogJumpLog $override override 0
Assert-DogJumpLog ($override.Replace('Debug assertions: enabled','Debug assertions: disabled')) override 0 Release
Assert-DogJumpLog ($log.Replace('validation_jump_default','validation_jump_explicit')) explicit 0
Assert-DogJumpLog ($override.Replace('validation_jump_override','validation_jump_damage').Replace('jump_right_0','stand_attack_1')) damage 0
$rejected = $false
try { Assert-DogJumpLog $log default 1 } catch { $rejected = $true }
if (!$rejected) { throw 'Accepted nonzero game exit' }
foreach ($bad in @($log.Replace('[dog jump]', '[other]'), $log.Replace('power=0.150000','power=0.110000'),
    $log.Replace('[dog jump] id=123','[dog jump] id=456'), $log.Replace('Debug assertions: enabled',''), ($log + "`nFATAL ERROR"), ($log + "`n[dog jump] id=123 section=validation_jump_default attack=stand_attack_1 power=0.150000 impulse=30.000000"))) {
    $rejected = $false
    try { Assert-DogJumpLog $bad default 0 } catch { $rejected = $true }
    if (!$rejected) { throw 'Accepted incomplete or incorrect jump evidence' }
}
foreach ($case in @('missing','empty','snork','pseudodog','chimera')) {
    $required = switch ($case) {
        'snork' { 'stand_attack_2_1' }; 'pseudodog' { 'run_jamp_1' }; 'chimera' { 'jump_attack_1' }; default { 'jump_right_0' }
    }
    $log = "Debug assertions: enabled`n[dog fixture] begin section=validation_jump_$case`nFATAL ERROR`nMissing attack parameters: section=validation_jump_$case animation=$required"
    Assert-DogJumpLog $log $case 0
    Assert-DogJumpLog ($log.Replace('Debug assertions: enabled','Debug assertions: disabled')) $case 0 Release
    $rejected = $false
    try { Assert-DogJumpLog ($log.Replace($required,'other')) $case 0 } catch { $rejected = $true }
    if (!$rejected) { throw 'Accepted unrelated failure' }
}
$root = Join-Path ([IO.Path]::GetTempPath()) ('ogsr-dog-' + [guid]::NewGuid())
New-Item -ItemType Directory $root | Out-Null
$root = (Resolve-Path -LiteralPath $root).Path
function Get-Process { param($Name, $ErrorAction) }
function Start-Process { throw 'Prepare-only fixture must not launch a process' }
try {
    New-Item -ItemType Directory "$root/bin_fixture", "$root/seed/savedgames", "$root/gamedata/config/misc", "$root/gamedata/scripts" | Out-Null
    Set-Content "$root/bin_fixture/xrEngine.exe" 'fixture'
    Set-Content "$root/seed/savedgames/bar_center.sav" 'save'
    Set-Content "$root/seed/user_ogsr.ltx" 'keypress_on_start on'
    Set-Content "$root/fsgame.ltx" '$app_data_root$ = true| false| $fs_root$| original\'
    Set-Content "$root/gamedata/config/misc/items.ltx" '[original]'
    Set-Content "$root/gamedata/scripts/_g.script" 'regular-config.lua'
    @{configuration='Debug';tracyEnabled=$false;sha256=(Get-FileHash "$root/bin_fixture/xrEngine.exe").Hash} |
        ConvertTo-Json | Set-Content "$root/bin_fixture/build.json"
    $paths = @('gamedata/config/misc/items.ltx','seed/savedgames/bar_center.sav','seed/user_ogsr.ltx','fsgame.ltx')
    $before = @($paths | ForEach-Object { (Get-FileHash "$root/$_").Hash })
    foreach ($case in @('default','explicit','override','damage','missing','empty','snork','pseudodog','chimera')) {
        $session = & "$PSScriptRoot/Run-DogJumpValidation.ps1" -InstallRoot $root -Package bin_fixture -SeedAppData seed -Case $case -PrepareOnly
        $meta = Get-Content "$session/session.json" -Raw | ConvertFrom-Json
        if ($meta.status -ne 'dog-prepared' -or $meta.case -ne $case -or !$meta.arguments.Contains('-dog_jump_probe') -or
            $meta.PSObject.Properties['gamePid'] -or
            !(Get-Content "$session/appdata/regular-config.lua" -Raw).Contains("section='validation_jump_$case'")) { throw 'Incorrect prepared dog scenario' }
        if ((Get-FileHash "$session/appdata/RegularDriver.lua").Hash -ne (Get-FileHash "$PSScriptRoot/DogJumpDriver.lua").Hash -or
            !(Get-Content "$session/fsgame.ltx" -Raw).Contains(("$session/appdata/" -replace '/', '\'))) { throw 'Dog session not isolated' }
    }
    $after = @($paths | ForEach-Object { (Get-FileHash "$root/$_").Hash })
    if (($before -join ',') -ne ($after -join ',')) { throw 'Original inputs modified' }
} finally {
    if ((Resolve-Path -LiteralPath $root).Path -ne $root -or (Split-Path -Leaf $root) -notmatch '^ogsr-dog-[0-9a-f-]{36}$') { throw 'Unexpected fixture path' }
    Remove-Item -LiteralPath $root -Recurse
}
