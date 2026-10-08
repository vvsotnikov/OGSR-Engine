function Assert-DogJumpLog([string]$Log, [string]$Case, [int]$ExitCode, [string]$Configuration = 'Debug') {
    $section = "validation_jump_$Case"
    $spawn = [regex]::Matches($Log, "\[dog fixture\] spawned id=(\d+) section=$section\b")
    if (($Configuration -eq 'Debug' -and $Log -notmatch 'Debug assertions: enabled') -or
        $Log -notmatch "\[dog fixture\] begin section=$section\b" -or $Log -match '\[dog fixture\] FAILED') {
        throw 'Dog fixture evidence incomplete'
    }
    $required = switch ($Case) {
        'missing' { 'jump_right_0' }
        'empty' { 'jump_right_0' }
        'fallback' { 'stand_attack_0' }
        'snork' { 'stand_attack_2_1' }
        'pseudodog' { 'run_jamp_1' }
        'chimera' { 'jump_attack_1' }
    }
    if ($required) {
        $expected = "Missing attack parameters: section=$section animation=$required"
        if ($Case -in @('missing','empty','fallback')) {
            $expected += '; set jump_attack_params_anim to a valid attack_params row'
        }
        $diagnostics = @($Log -split '\r?\n' | Where-Object { $_ -match '^(?:\[error\]Description\s*:\s*)?Missing attack parameters:' })
        $expectedLine = @($diagnostics | Where-Object {
            ($_ -replace '^\[error\]Description\s*:\s*', '').TrimEnd() -ceq $expected
        })
        $fatal = $Log.IndexOf('FATAL ERROR')
        if ($fatal -lt 0 -or $expectedLine.Count -ne 1 -or $diagnostics.Count -ne 1 -or
            $Log -match "\[dog jump\] id=\d+ section=$section " -or $Log -match '\[dog fixture\] complete') {
            throw 'Expected attack-parameter rejection missing'
        }
        Assert-ValidationLogHealthy $Log.Substring(0, $fatal)
        return
    }
    if ($spawn.Count -ne 3) { throw 'Expected three test dogs' }
    Assert-ValidationLogHealthy $Log
    $expected = switch ($Case) {
        'default' { 'attack=stand_attack_0 power=0.150000 impulse=30.000000' }
        'explicit' { 'attack=stand_attack_0 power=0.150000 impulse=30.000000' }
        'override' { 'attack=jump_right_0 power=0.370000 impulse=47.000000' }
        'damage' { 'attack=stand_attack_1 power=0.370000 impulse=47.000000' }
        default { throw 'Unknown dog case' }
    }
    $hits = @($spawn | Where-Object { $Log.Contains("[dog jump] id=$($_.Groups[1].Value) section=$section $expected") })
    foreach ($event in [regex]::Matches($Log, "\[dog jump\] id=(\d+) section=$section ([^\r\n]+)")) {
        if ($event.Groups[1].Value -notin @($spawn | ForEach-Object { $_.Groups[1].Value }) -or $event.Groups[2].Value -cne $expected) {
            throw 'Wrong dog jump parameters or identity'
        }
    }
    if ($ExitCode -ne 0 -or $Log -notmatch '\[dog fixture\] complete' -or !$hits.Count) {
        throw 'Dog jump evidence incomplete'
    }
}
