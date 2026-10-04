param()
$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('ogsr-group-runner-test-' + [guid]::NewGuid())
$seed = "$root/seeds/bar-2026-10-03"
New-Item -ItemType Directory -Path "$root/bin_group_cleanup", "$root/tools", "$seed/savedgames", "$root/gamedata/config/misc" | Out-Null
Set-Content "$root/bin_group_cleanup/xrEngine.exe" 'fixture'
Set-Content "$seed/user_ogsr.ltx" 'fixture'
Set-Content "$seed/savedgames/bar_center.sav" 'fixture'
Set-Content "$root/fsgame-profiler.ltx" '$app_data_root$ = unused'
$config = "$root/gamedata/config/misc/items.ltx"
# Non-ASCII bytes and no final newline must survive restoration exactly.
$original = [byte[]](91,116,101,115,116,93,13,10,59,255,128)
[IO.File]::WriteAllBytes($config, $original)
$before = (Get-FileHash $config).Hash
function Start-Process {
    param($FilePath, $ArgumentList, $WorkingDirectory, [switch]$PassThru)
    if (!(Select-String -LiteralPath $config -SimpleMatch '[validation_online_group]' -Quiet)) { throw 'Missing temporary section' }
    if ($scenario -eq 'launch-failure') { throw 'Injected launch failure' }
    if ($ArgumentList -notmatch '-fsltx (\S+)') { throw 'Missing session config' }
    $session = Split-Path (Join-Path $WorkingDirectory $Matches[1])
    New-Item -ItemType Directory "$session/appdata/logs" | Out-Null
    $log = if ($scenario -eq 'bad-log') { 'incomplete' } else {
        'empty_group_cleared far_group_cleared group_online member_client=1 complete mode=save Game group_validation.sav is successfully saved'
    }
    Set-Content "$session/appdata/logs/test.log" $log
    $process = [pscustomobject]@{Id=123;ExitCode=0;HasExited=$true}
    $process | Add-Member ScriptMethod WaitForExit { param($timeout) return $true }
    return $process
}
foreach ($scenario in @('success','launch-failure','bad-log')) {
    $failed = $false
    try { & "$PSScriptRoot/Run-GroupCleanupValidation.ps1" -InstallRoot $root -ToolRoot "$root/tools" | Out-Null }
    catch {
        if ($scenario -eq 'success' -or $_.Exception.Message -notmatch 'Injected launch failure|Missing evidence:') { throw }
        $failed = $true
    }
    if ($failed -ne ($scenario -ne 'success')) { throw "Unexpected result: $scenario" }
    if ((Get-FileHash $config).Hash -ne $before) { throw "Configuration changed after $scenario" }
}
Write-Output 'Group configuration restored byte-for-byte after success, launch failure and log failure'

Add-Content -LiteralPath $config -Value "`n[validation_online_group]`nclass = ON_OFF_G" -Encoding ascii
$contaminated = (Get-FileHash $config).Hash
$sessionsBefore = @(Get-ChildItem "$root/captures" -Directory).Count
$rejected = $false
try { & "$PSScriptRoot/Run-GroupCleanupValidation.ps1" -InstallRoot $root -ToolRoot "$root/tools" | Out-Null }
catch {
    if ($_.Exception.Message -notlike 'Existing [[]validation_online_group]*') { throw }
    $rejected = $true
}
if (!$rejected) { throw 'Accepted leftover test section' }
if ((Get-FileHash $config).Hash -ne $contaminated -or @(Get-ChildItem "$root/captures" -Directory).Count -ne $sessionsBefore) {
    throw 'Interrupted-run detection modified configuration or created misleading evidence'
}
Write-Output 'Leftover group section rejected without modifying configuration or creating a session'
