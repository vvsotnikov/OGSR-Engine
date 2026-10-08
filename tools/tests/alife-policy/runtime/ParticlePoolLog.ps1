function Assert-ParticlePoolLog([string]$Log, [int]$ExitCode) {
    Assert-ValidationLogHealthy $Log
    $phases = @([regex]::Matches($Log, '\[particle pool\] phase=(\d+) ') |
        ForEach-Object { $_.Groups[1].Value })
    if ($ExitCode -ne 0 -or $Log -notmatch 'Debug assertions: enabled' -or
        $Log -match '\[particle pool\] FAILED' -or
        $Log -notmatch '\[particle pool\] reused-after-child-reset group=\S+' -or
        $Log -notmatch '\[particle pool\] complete' -or ($phases -join ',') -ne '1,2,3,4,5') {
        throw 'Particle validation evidence incomplete'
    }
}
