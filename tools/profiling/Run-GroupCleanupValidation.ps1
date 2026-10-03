param(
    [Parameter(Mandatory)][string]$InstallRoot,
    [Parameter(Mandatory)][string]$ToolRoot,
    [string]$ReloadSession = ''
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/ValidationLog.ps1"
$package = 'bin_group_cleanup'
$seed = 'seeds/bar-2026-10-03'; $save = 'bar_center'
if ($ReloadSession) {
    $source = Get-Content -Raw "$ReloadSession/session.json" | ConvertFrom-Json
    if ($source.status -ne 'group-cleanup-completed') { throw 'Reload source did not pass' }
    $seed = [IO.Path]::GetRelativePath((Resolve-Path $InstallRoot).Path, (Resolve-Path "$ReloadSession/appdata").Path); $save = 'group_validation'
}
$session = & "$PSScriptRoot/Capture-Session.ps1" -InstallRoot $InstallRoot -ToolRoot $ToolRoot -Package $package -Mode distance -SeedAppData $seed -SaveName $save -PrepareOnly
# Only the isolated validation installation receives this server-only test section.
$config = "$InstallRoot/gamedata/config/misc/items.ltx"
if (!(Select-String -LiteralPath $config -SimpleMatch '[validation_online_group]' -Quiet)) {
    Copy-Item $config "$session/items-before-group-test.ltx"
    Add-Content -LiteralPath $config -Value "`n[validation_online_group]`nclass = ON_OFF_G`n" -Encoding ascii
}
$metaPath = "$session/session.json"
$meta = Get-Content -Raw $metaPath | ConvertFrom-Json
$meta.arguments = $meta.arguments.Replace(' -alife_metrics','') + ' -group_cleanup_validation'
if ($ReloadSession) {
    Copy-Item "$ReloadSession/appdata/group-ids.txt" "$session/appdata/group-ids.txt"
    $meta.arguments += ' -group_cleanup_reload'
}
$meta.status = 'group-cleanup-running'
$game = Start-Process "$InstallRoot/$package/xrEngine.exe" -ArgumentList $meta.arguments -WorkingDirectory $InstallRoot -PassThru
$meta | Add-Member gamePid $game.Id
$meta | ConvertTo-Json -Depth 8 | Set-Content $metaPath -Encoding utf8
Write-Output "START group cleanup session=$session"
try {
    if (!$game.WaitForExit(120000)) { Stop-Process -Id $game.Id; throw 'Group cleanup test timed out' }
    $logs = @(Get-ChildItem "$session/appdata/logs" -Filter '*.log')
    if ($logs.Count -ne 1) { throw 'Expected one log' }
    $log = Get-Content -Raw $logs[0].FullName
    Assert-ValidationLogHealthy $log
    $expected = if ($ReloadSession) { @('restored group=','complete mode=reload','Game group_reloaded.sav is successfully saved') } else { @('empty_group_cleared','far_group_cleared','group_online member_client=1','complete mode=save','Game group_validation.sav is successfully saved') }
    foreach ($marker in $expected) { if (!$log.Contains($marker)) { throw "Missing evidence: $marker" } }
    if ($game.ExitCode -ne 0) { throw 'Abnormal game exit' }
    $meta.status = 'group-cleanup-completed'
    $meta | Add-Member gameExitCode $game.ExitCode
    Write-Output "COMPLETE group cleanup session=$session"
} catch {
    $meta.status = 'group-cleanup-failed'
    $meta | Add-Member failure $_.Exception.Message
    throw
} finally {
    $meta | ConvertTo-Json -Depth 8 | Set-Content $metaPath -Encoding utf8
}
