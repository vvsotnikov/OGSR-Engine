param(
    [Parameter(Mandatory)][string]$InstallRoot,
    [Parameter(Mandatory)][string]$ToolRoot,
    [string]$SeedAppData = 'seeds/bar-2026-10-03',
    [string]$SaveName = 'bar_center',
    [switch]$RestartOnly,
    [string]$ExistingSession,
    [switch]$Manual
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/ValidationLog.ps1"
# Requires persistence-diagnostic.patch in a separately packaged bin_validation.
$session = $ExistingSession
if (!$session) {
    $session = & "$PSScriptRoot/Capture-Session.ps1" -InstallRoot $InstallRoot -ToolRoot $ToolRoot `
        -Package bin_validation -Mode whole-map -SeedAppData $SeedAppData -SaveName $SaveName -PrepareOnly
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
function Wait-Stage([string]$Stage, [string]$Command, [string]$SuccessPattern, [int]$Level, [int]$Count = 3) {
    Wait-For { Test-ValidationStage -Text (Read-Log) -Command $Command -SuccessPattern $SuccessPattern -Level $Level -MinimumSnapshots $Count } $Stage
    [IO.File]::WriteAllText((Join-Path $session "$Stage.log"), (Read-Log))
}
try {
    Wait-Stage 'initial' '' '' 7
    if (!$RestartOnly) {
        Send-Command 'save validation_bar'
        Wait-Stage 'saved' 'save validation_bar' 'Game validation_bar\.sav is successfully saved' 7 1
        if (!(Test-Path "$session/appdata/savedgames/validation_bar.sav")) { throw 'Save acknowledgement without a save file' }
        Send-Command 'load validation_bar'
        Wait-Stage 'reloaded' 'load validation_bar' 'Game validation_bar is successfully loaded' 7
        Send-Command 'jump_to_level l02_garbage'
        Wait-Stage 'garbage' 'jump_to_level l02_garbage' 'Game \S+_autosave is successfully loaded' 2
        Send-Command 'jump_to_level l05_bar'
        Wait-Stage 'bar-return' 'jump_to_level l05_bar' 'Game \S+_autosave is successfully loaded' 7
    }
    Send-Command 'quit'
    if (!$game.WaitForExit(30000)) { throw 'Normal quit did not finish within 30 seconds' }
    Assert-ValidationLogHealthy (Read-Log)
    if ($null -ne $game.ExitCode -and $game.ExitCode -ne 0) { throw "Engine exited with code $($game.ExitCode)" }
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
