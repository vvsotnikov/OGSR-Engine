. "$PSScriptRoot/ValidationLog.ps1"
Assert-ValidationLogHealthy 'ordinary engine output'
foreach ($message in @('FATAL ERROR','SCRIPT ERROR','SCRIPT RUNTIME ERROR','LUA ERROR', '[LogStackTrace] ExceptionCode: [c0000005]', 'Scheduler tried to update object snork')) {
    $rejected = $false
    try { Assert-ValidationLogHealthy $message } catch { $rejected = $true }
    if (!$rejected) { throw "Accepted engine failure: $message" }
}
Write-Output 'Engine error detection passed'
