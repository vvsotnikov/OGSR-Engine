function Assert-PhysicsReloadLog([string]$Log, [int]$ExitCode, [string]$Mode) {
    Assert-ValidationLogHealthy $Log
    Assert-PolicyMessages $Log $Mode 3 $false
    $stages = [regex]::Match($Log, '(?s)\[physics reload\] saved_world_loaded(.*?)\[physics reload\] complete')
    if ($ExitCode -ne 0 -or $Log -match '\[physics reload\] FAILED' -or !$stages.Success -or
        $stages.Groups[1].Value -notmatch '\[physics reload\] partial_shell object=\d+ hidden=[1-9]\d* elements=[1-9]\d*' -or
        $stages.Groups[1].Value -notmatch 'Game physics_reload\.sav is successfully saved') {
        throw 'Physics reload evidence incomplete'
    }
}
