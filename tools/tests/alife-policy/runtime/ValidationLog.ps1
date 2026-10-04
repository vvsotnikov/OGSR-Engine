# Shared by the live harness and offline evidence reader. No engine dependency.
function Assert-ValidationLogHealthy {
    param([AllowEmptyString()][string]$Text)
    if ($Text -match '(?im)^.*(?:FATAL ERROR|SCRIPT (?:RUNTIME )?ERROR|LUA ERROR).*$') {
        throw "Engine error during validation: $($Matches[0])"
    }
}

function Get-ValidationSnapshots {
    param([AllowEmptyString()][string]$Text, [switch]$AllowIncomplete)
    $current = $null
    $stage = 'initial'
    foreach ($line in ($Text -split "`n")) {
        if ($line -match '\[ALife validation\] command=(.+) allowed=1') { $stage = $Matches[1].Trim() }
        if ($line -match '\[ALife world begin\] game_ms=(\d+) level=(\d+)') {
            if ($null -ne $current) { throw 'Nested world snapshot: evidence is incomplete' }
            $current = [ordered]@{stage=$stage; game_ms=[uint32]$Matches[1]; level=[int]$Matches[2]; entities=[Collections.Generic.List[object]]::new()}
        } elseif ($line -match '\[ALife world\] (.+)') {
            if ($null -eq $current) { throw 'Creature record outside a world snapshot' }
            $fields = $Matches[1].Trim()
            if ($fields -notmatch '^id=\d+ section=\S+ graph=\d+ level=\d+ online=[01] parent=\d+ group=\d+ health=-?\d+\.\d+ flags=\d+$') {
                # A writer may be midway through the very last line of a live log.
                if ($AllowIncomplete -and $line -eq ($Text -split "`n")[-1]) { break }
                throw "Malformed creature record: $fields"
            }
            $entity = [ordered]@{}
            foreach ($field in $fields.Split(' ')) {
                $pair = $field.Split('=', 2)
                $entity[$pair[0]] = $pair[1]
            }
            $current.entities.Add([pscustomobject]$entity)
        } elseif ($line -match '\[ALife world end\]') {
            if ($null -eq $current -or $current.entities.Count -eq 0) { throw 'Empty or unmatched world snapshot' }
            [pscustomobject]$current
            $current = $null
        }
    }
    if ($null -ne $current -and !$AllowIncomplete) { throw 'Truncated world snapshot at end of log' }
}

function Test-ValidationStage {
    param([string]$Text, [string]$Command, [string]$SuccessPattern, [int]$Level, [int]$MinimumSnapshots = 3)
    Assert-ValidationLogHealthy $Text
    if ($Command) {
        $marker = "[ALife validation] command=$Command allowed=1"
        $offset = $Text.LastIndexOf($marker, [StringComparison]::Ordinal)
        if ($offset -lt 0) { return $false }
        $Text = $Text.Substring($offset)
    }
    if ($SuccessPattern) {
        $success = [regex]::Match($Text, $SuccessPattern)
        if (!$success.Success) { return $false }
        $Text = $Text.Substring($success.Index + $success.Length)
    }
    $snapshots = @(Get-ValidationSnapshots -Text $Text -AllowIncomplete)
    # Require consecutive final samples on the destination, not just any new output.
    if ($snapshots.Count -lt $MinimumSnapshots) { return $false }
    $last = @($snapshots | Select-Object -Last $MinimumSnapshots)
    foreach ($snapshot in $last) {
        if (@($snapshot.entities | Group-Object id | Where-Object Count -gt 1).Count) { throw 'Duplicate creature IDs in snapshot' }
        if (@($snapshot.entities | Where-Object { $_.online -eq '1' -and [int]$_.level -ne $snapshot.level }).Count) {
            throw 'Online creature on an unloaded map'
        }
    }
    return @($last | Where-Object { $_.level -ne $Level }).Count -eq 0
}
