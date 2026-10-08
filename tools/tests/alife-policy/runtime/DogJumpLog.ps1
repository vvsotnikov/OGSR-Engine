function Assert-DogJumpLog([string]$Log, [string]$Case, [int]$ExitCode) {
    $section = "validation_jump_$Case"
    $spawn = [regex]::Matches($Log, "\[dog fixture\] spawned id=(\d+) section=$section\b")
    if ($spawn.Count -lt 1 -or $spawn.Count -gt 3 -or $Log -notmatch 'Debug assertions: enabled' -or $Log -match '\[dog fixture\] FAILED') {
        throw 'Dog fixture evidence incomplete'
    }
    if ($Case -in @('missing','empty')) {
        $fatal = $Log.IndexOf('FATAL ERROR')
        if ($fatal -lt 0 -or $Log -notmatch "Missing attack parameters: section=$section animation=stand_attack_1" -or
            $Log -match "\[dog jump\] id=\d+ section=$section " -or $Log -match '\[dog fixture\] complete') {
            throw 'Expected attack-parameter rejection missing'
        }
        Assert-ValidationLogHealthy $Log.Substring(0, $fatal)
        return
    }
    Assert-ValidationLogHealthy $Log
    $expected = switch ($Case) {
        'default' { 'attack=stand_attack_0 power=0.150000 impulse=30.000000' }
        'override' { 'attack=stand_attack_1 power=0.370000 impulse=47.000000' }
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
