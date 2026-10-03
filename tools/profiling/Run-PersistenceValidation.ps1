param(
    [string]$InstallRoot = 'D:\Games\OGSR-Baseline',
    [string]$ToolRoot = 'C:\Users\vladimir\Documents\Codex\tools\tracy',
    [string]$SeedAppData = 'seeds/bar-2026-10-03',
    [string]$SaveName = 'bar_center',
    [switch]$RestartOnly,
    [string]$ExistingSession,
    [switch]$Manual
)
$ErrorActionPreference = 'Stop'
# Requires persistence-diagnostic.patch in a separately packaged bin_validation.
$session = $ExistingSession
if (!$session) {
    $session = & "$PSScriptRoot/Capture-Session.ps1" -InstallRoot $InstallRoot -ToolRoot $ToolRoot `
        -Mode whole-map -SeedAppData $SeedAppData -SaveName $SaveName -PrepareOnly
}
$metaPath = Join-Path $session 'session.json'
$meta = Get-Content -Raw $metaPath | ConvertFrom-Json
$engine = Join-Path $InstallRoot 'bin_validation/xrEngine.exe'
if ($meta.arguments -notmatch '-alife_validation') { $meta.arguments += ' -alife_validation' }
$meta.engineSha256 = (Get-FileHash $engine).Hash
$meta.build = Get-Content -Raw "$InstallRoot/bin_validation/build.json" | ConvertFrom-Json
$meta.status = 'validation-running'
if ($ExistingSession) {
    $game = Get-Process -Id $meta.gamePid
    if ($game.Path -ne $engine) { throw 'Session process does not match validation executable' }
    if (Get-ChildItem "$session/appdata" -Filter 'validation_*.txt') { throw 'Cannot resume after commands have been published' }
    if ($meta.PSObject.Properties['failure']) {
        $meta | Add-Member -NotePropertyName priorHarnessFailure -NotePropertyValue $meta.failure -Force
        $meta.PSObject.Properties.Remove('failure')
    }
} else {
    $game = Start-Process -FilePath $engine -ArgumentList $meta.arguments -WorkingDirectory $InstallRoot -PassThru
}
$meta | Add-Member -NotePropertyName gamePid -NotePropertyValue $game.Id -Force
$meta | ConvertTo-Json -Depth 8 | Set-Content $metaPath -Encoding utf8
Write-Output "SESSION=$session PID=$($game.Id)"
if ($Manual) {
    $meta.status = 'manual-validation-running'
    $meta | ConvertTo-Json -Depth 8 | Set-Content $metaPath -Encoding utf8
    Write-Output 'Walk from Bar to Garbage through the normal level changer, return, try a conversation/task, save, and quit normally. No commands or Tracy capture will be sent.'
    return
}
$script:logPath = $null
$script:commandNumber = 0
function Read-Log {
    if (!$script:logPath) {
        $found = Get-ChildItem "$session/appdata/logs" -Filter '*.log' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $script:logPath = $found.FullName }
    }
    if ($script:logPath) {
        $stream = [IO.File]::Open($script:logPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        $reader = [IO.StreamReader]::new($stream)
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    }
    return ''
}
function Wait-For([scriptblock]$Condition, [string]$Description) {
    $deadline = (Get-Date).AddSeconds(150)
    do {
        $game.Refresh()
        if ($game.HasExited) { throw "Engine exited during $Description; exit=$($game.ExitCode)" }
        if (& $Condition) { Write-Output "PASS: $Description"; return }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)
    throw "Timed out: $Description"
}
function Send-Command([string]$Command) {
    $script:commandNumber++
    $path = Join-Path $session ('appdata/validation_{0:000}.txt' -f $script:commandNumber)
    [IO.File]::WriteAllText("$path.pending", "$Command`n", [Text.Encoding]::ASCII)
    Move-Item -LiteralPath "$path.pending" -Destination $path
    Write-Output "SENT: $Command"
}
function Wait-Snapshots([int]$Target, [string]$Stage) {
    Wait-For { ([regex]::Matches((Read-Log), '\[ALife world end\]')).Count -ge $Target } $Stage
    [IO.File]::WriteAllText((Join-Path $session "$Stage.log"), (Read-Log))
}
try {
    Wait-Snapshots 3 'initial'
    if (!$RestartOnly) {
        Send-Command 'save validation_bar'
        Wait-For { Test-Path "$session/appdata/savedgames/validation_bar.sav" } 'save-created'
        $count = ([regex]::Matches((Read-Log), '\[ALife world end\]')).Count
        Wait-Snapshots ($count + 1) 'saved'
        Send-Command 'load validation_bar'
        Wait-Snapshots ($count + 4) 'reloaded'
        $count = ([regex]::Matches((Read-Log), '\[ALife world end\]')).Count
        Send-Command 'jump_to_level l02_garbage'
        Wait-Snapshots ($count + 3) 'garbage'
        $count = ([regex]::Matches((Read-Log), '\[ALife world end\]')).Count
        Send-Command 'jump_to_level l05_bar'
        Wait-Snapshots ($count + 3) 'bar-return'
    }
    Send-Command 'quit'
    if (!$game.WaitForExit(30000)) { throw 'Normal quit did not finish within 30 seconds' }
    $meta.status = 'validation-completed'
    $meta | Add-Member -NotePropertyName gameExitCode -NotePropertyValue $game.ExitCode -Force
    Write-Output "EXIT=$($game.ExitCode) SESSION=$session"
} catch {
    $meta.status = 'validation-failed'
    $meta | Add-Member -NotePropertyName failure -NotePropertyValue $_.Exception.Message -Force
    # Preserve a failed live session for investigation; never kill an unrelated game.
    throw
} finally {
    $meta | ConvertTo-Json -Depth 8 | Set-Content $metaPath -Encoding utf8
}
