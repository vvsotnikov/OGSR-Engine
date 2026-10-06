$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/CheckoutMetadata.ps1"
$repo = [IO.Path]::GetFullPath($PSScriptRoot)
$revision = '0123456789012345678901234567890123456789'
$case = ''
function git {
    $global:LASTEXITCODE = 0
    if ($case -eq 'throw') { throw 'Git unavailable' }
    if ($args -contains '--show-toplevel') {
        if ($case -eq 'no-repository') { $global:LASTEXITCODE=128; return }
        if ($case -eq 'parent-repository') { return [IO.Path]::GetDirectoryName($repo) }
        return $repo
    }
    if ($args -contains 'HEAD') {
        if ($case -eq 'no-head') { $global:LASTEXITCODE=128; return }
        if ($case -eq 'bad-head') { return 'not-a-commit' }
        return $revision
    }
    if ($case -eq 'failed-status') { $global:LASTEXITCODE=1; return }
    if ($case -eq 'dirty') { return ' M source.cpp' }
}
foreach ($case in @('no-repository','parent-repository','no-head','bad-head','failed-status','throw')) {
    $result=Read-CheckoutMetadata $repo
    if ($null -ne $result.sourceCommitAtLaunch -or $null -ne $result.sourceDirtyAtLaunch) {
        throw "Git failure reported known metadata: $case"
    }
}
foreach ($case in @('clean','dirty')) {
    $result=Read-CheckoutMetadata $repo
    if ($result.sourceCommitAtLaunch -ne $revision -or $result.sourceDirtyAtLaunch -isnot [bool] -or
        $result.sourceDirtyAtLaunch -ne ($case -eq 'dirty')) { throw "Incorrect checkout metadata: $case" }
}
# Source exports can run without Git installed at all.
function Get-Command { param($Name, $ErrorAction) }
$result=Read-CheckoutMetadata $repo
if ($null -ne $result.sourceCommitAtLaunch -or $null -ne $result.sourceDirtyAtLaunch) { throw 'Missing Git reported known metadata' }
Write-Output 'Checkout metadata handles valid revisions and unavailable/failed Git'
