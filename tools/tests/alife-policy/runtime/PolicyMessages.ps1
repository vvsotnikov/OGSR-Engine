function Assert-PolicyMessages([string]$Log, [string]$Mode, [int]$Loads, [bool]$DistanceChanged) {
    $startup = @([regex]::Matches($Log, '\* ALife policy: whole-map \(EXPERIMENTAL\);')).Count
    $setter = @([regex]::Matches($Log, '\* ALife whole-map policy: switch distance/factor changes are stored but do not control switching')).Count
    if ($Mode -eq 'whole-map') {
        if ($startup -ne $Loads) { throw 'Missing or repeated whole-map startup message' }
        if ($DistanceChanged -and $setter -ne $Loads) { throw 'Missing or repeated whole-map distance override message' }
        if ($setter -gt $Loads) { throw 'Repeated whole-map distance override message' }
    } elseif ($startup -ne 0 -or $setter -ne 0) {
        throw 'Distance-mode run reported whole-map policy'
    }
}
