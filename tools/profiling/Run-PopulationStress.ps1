param(
    [ValidateRange(0,400)][int[]]$Counts = @(0,50,100,200,400),
    [string]$InstallRoot = 'D:\Games\OGSR-Baseline',
    [string]$ToolRoot = 'C:\Users\vladimir\Documents\Codex\tools\tracy',
    [switch]$CaptureTrace
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/ValidationLog.ps1"
$engine = Join-Path $InstallRoot 'bin_stress/xrEngine.exe'
foreach ($count in $Counts) {
    $session = & "$PSScriptRoot/Capture-Session.ps1" -InstallRoot $InstallRoot -ToolRoot $ToolRoot `
        -SeedAppData 'seeds/bar-2026-10-03' -SaveName bar_center -Mode whole-map -PrepareOnly
    $path = Join-Path $session 'session.json'
    $meta = Get-Content -Raw $path | ConvertFrom-Json
    $meta.arguments += " -alife_stress $count"
    $meta.engineSha256 = (Get-FileHash $engine).Hash
    $meta.build = Get-Content -Raw "$InstallRoot/bin_stress/build.json" | ConvertFrom-Json
    $meta.status = 'stress-running'
    $meta | Add-Member requestedExtraStalkers $count
    $meta | Add-Member traceRequested ([bool]$CaptureTrace)
    $collector = $null
    $game = Start-Process $engine -ArgumentList $meta.arguments -WorkingDirectory $InstallRoot -PassThru
    $meta | Add-Member gamePid $game.Id
    $meta | ConvertTo-Json -Depth 8 | Set-Content $path -Encoding utf8
    Write-Output "START count=$count session=$session pid=$($game.Id)"
    try {
        $deadline = (Get-Date).AddSeconds(240)
        while (!$game.WaitForExit(2000)) {
            if ($CaptureTrace -and !$collector) {
                $logFile = Get-ChildItem "$session/appdata/logs" -Filter '*.log' -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($logFile) {
                    $stream = [IO.File]::Open($logFile.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
                    $reader = [IO.StreamReader]::new($stream)
                    try { $live = $reader.ReadToEnd() } finally { $reader.Dispose() }
                    if ($live -match '\[stress\] measure_begin') {
                        $captureArgs = '-a 127.0.0.1 -o "' + $session + '\capture.tracy" -s 35 -m 20'
                        $collector = Start-Process "$ToolRoot/bin/tracy-capture.exe" -ArgumentList $captureArgs -WindowStyle Hidden -PassThru `
                            -RedirectStandardOutput "$session/capture.stdout.log" -RedirectStandardError "$session/capture.stderr.log"
                        Write-Output "TRACE count=$count capturePid=$($collector.Id)"
                    }
                }
            }
            if ((Get-Date) -gt $deadline) {
                $game.Refresh()
                if ($game.Path -eq $engine) { Stop-Process -Id $game.Id }
                throw 'Stress session exceeded 240 seconds; own disposable process stopped'
            }
        }
        if ($CaptureTrace) {
            if (!$collector) { throw 'Tracy collector was never started' }
            if (!$collector.WaitForExit(60000)) { throw 'Tracy collector has not finished saving' }
            if ($collector.ExitCode -ne 0 -or !(Test-Path "$session/capture.tracy")) { throw 'Tracy capture failed' }
            $meta | Add-Member traceBytes (Get-Item "$session/capture.tracy").Length
        }
        $logs = @(Get-ChildItem "$session/appdata/logs" -Filter '*.log')
        if ($logs.Count -ne 1) { throw 'Expected one stress log' }
        $log = [IO.File]::ReadAllText($logs[0].FullName)
        Assert-ValidationLogHealthy $log
        if ($game.ExitCode -ne 0 -or $log -match '\[stress\] invalid' -or $log -notmatch '\[stress\] measure_end') {
            throw "Incomplete stress run; exit=$($game.ExitCode)"
        }
        if ($log -notmatch "\[stress\] spawn_complete requested=$count created=$count ") { throw 'Spawn count did not match request' }
        $meta.status = 'stress-completed'
        $meta | Add-Member gameExitCode $game.ExitCode
        Write-Output "COMPLETE count=$count session=$session"
    } catch {
        $meta.status = 'stress-failed'
        $meta | Add-Member failure $_.Exception.Message
        throw
    } finally {
        $meta | ConvertTo-Json -Depth 8 | Set-Content $path -Encoding utf8
    }
}
