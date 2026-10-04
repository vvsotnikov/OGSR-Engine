. "$PSScriptRoot/ValidationLog.ps1"
Assert-ValidationLogHealthy 'ordinary engine output'
foreach ($message in @('FATAL ERROR','SCRIPT ERROR','SCRIPT RUNTIME ERROR','LUA ERROR')) {
    $rejected = $false
    try { Assert-ValidationLogHealthy $message } catch { $rejected = $true }
    if (!$rejected) { throw "Accepted engine failure: $message" }
}
Write-Output 'Engine error detection passed'
