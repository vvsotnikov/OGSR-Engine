$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/ValidationLog.ps1"
$script:passed = 0
function Check([string]$Name, [scriptblock]$Body) {
    & $Body
    $script:passed++
    Write-Output "PASS: $Name"
}
function Expect-Error([scriptblock]$Body) {
    $caught = $false
    try { & $Body | Out-Null } catch { $caught = $true }
    if (!$caught) { throw 'Expected failure but operation succeeded' }
}
function Snapshot([int]$Level = 7, [string]$Entity = '') {
    if (!$Entity) { $Entity = "id=1 section=actor graph=100 level=$Level online=1 parent=65535 group=65535 health=1.000000 flags=1" }
    return "[ALife world begin] game_ms=1000 level=$Level`n[ALife world] $Entity`n[ALife world end]`n"
}
$bar = Snapshot
$garbage = Snapshot 2
$marker = "[ALife validation] command=jump_to_level l02_garbage allowed=1`n"
$success = "Game tester_autosave is successfully loaded`n"
$pattern = 'Game \S+_autosave is successfully loaded'
Check 'successful acknowledged transition' {
    if (!(Test-ValidationStage ($marker + $success + $garbage * 3) 'jump_to_level l02_garbage' $pattern 2)) { throw 'Expected pass' }
}
Check 'ignored command cannot pass from unrelated snapshots' {
    if (Test-ValidationStage ($garbage * 4) 'jump_to_level l02_garbage' $pattern 2) { throw 'False pass' }
}
Check 'missing load acknowledgement fails' {
    if (Test-ValidationStage ($marker + $garbage * 3) 'jump_to_level l02_garbage' $pattern 2) { throw 'False pass' }
}
Check 'failed transition that stays in Bar fails' {
    if (Test-ValidationStage ($marker + $success + $bar * 3) 'jump_to_level l02_garbage' $pattern 2) { throw 'False pass' }
}
Check 'old destination samples do not hide a wrong final level' {
    if (Test-ValidationStage ($marker + $success + $garbage * 3 + $bar) 'jump_to_level l02_garbage' $pattern 2) { throw 'False pass' }
}
Check 'truncated offline evidence is rejected' {
    Expect-Error { Get-ValidationSnapshots ($bar + '[ALife world begin] game_ms=2000 level=7') }
}
Check 'live unfinished snapshot is not counted' {
    $result = @(Get-ValidationSnapshots ($bar + '[ALife world begin] game_ms=2000 level=7') -AllowIncomplete)
    if ($result.Count -ne 1) { throw 'Wrong number of complete samples' }
}
Check 'missing health cannot silently become zero' {
    Expect-Error { Get-ValidationSnapshots ($bar.Replace(' health=1.000000', '')) }
}
Check 'nested snapshots cannot hide missing data' {
    Expect-Error { Get-ValidationSnapshots ("[ALife world begin] game_ms=0 level=7`n" + $bar) }
}
Check 'unmatched end marker rejected' { Expect-Error { Get-ValidationSnapshots '[ALife world end]' } }
Check 'online entity on another map rejected' {
    Expect-Error { Test-ValidationStage ($bar.Replace('graph=100 level=7', 'graph=100 level=2') * 3) '' '' 7 }
}
Check 'duplicate IDs rejected' {
    $duplicate = $bar.Replace('[ALife world end]', "[ALife world] id=1 section=actor graph=100 level=7 online=1 parent=65535 group=65535 health=1.000000 flags=1`n[ALife world end]")
    Expect-Error { Test-ValidationStage ($duplicate * 3) '' '' 7 }
}
Check 'script errors cannot pass despite sufficient snapshots' {
    Expect-Error { Test-ValidationStage ("SCRIPT RUNTIME ERROR: test`n" + $bar * 3) '' '' 7 }
}
Check 'known OpenAL warning does not masquerade as a script failure' {
    Assert-ValidationLogHealthy 'OpenAL AL_STOP_SOURCES_ON_DISCONNECT_SOFT error: Invalid Enum'
}
Write-Output "$script:passed validation-log checks passed."
