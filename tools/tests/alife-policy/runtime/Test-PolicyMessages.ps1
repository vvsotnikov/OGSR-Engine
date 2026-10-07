$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/PolicyMessages.ps1"
$startup='* ALife policy: whole-map (EXPERIMENTAL); switch_distance remains configured but does not control switching'
$setter='* ALife whole-map policy: switch distance/factor changes are stored but do not control switching'
$both="$startup`n$setter`n"
Assert-PolicyMessages $both whole-map 1 $true
Assert-PolicyMessages ($both*3) whole-map 3 $true
Assert-PolicyMessages $startup whole-map 1 $false
Assert-PolicyMessages '' distance 1 $true
foreach ($case in @(
    @{log=$setter; mode='whole-map'; loads=1; changed=$true},
    @{log=$startup; mode='whole-map'; loads=1; changed=$true},
    @{log=$both+$setter; mode='whole-map'; loads=1; changed=$true},
    @{log=$both*2; mode='whole-map'; loads=3; changed=$true},
    @{log=$both; mode='distance'; loads=1; changed=$true}
)) {
    $failed=$false
    try { Assert-PolicyMessages $case.log $case.mode $case.loads $case.changed } catch { $failed=$true }
    if (!$failed) { throw 'Missing, repeated or wrong-mode policy messages were accepted' }
}
Write-Output 'Policy message checks reject missing/repeated records and wrong-mode messages'
