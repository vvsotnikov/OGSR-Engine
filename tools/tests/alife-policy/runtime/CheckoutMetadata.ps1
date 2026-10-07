function Read-CheckoutMetadata([string]$Repo) {
    $unknown = @{ sourceCommitAtLaunch = $null; sourceDirtyAtLaunch = $null }
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (!$git) { return $unknown }
    try {
        $top = & $git -C $Repo rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -ne 0 -or !$top -or
            [IO.Path]::GetFullPath($top) -ne [IO.Path]::GetFullPath($Repo)) { return $unknown }
        $revision = & $git -C $Repo rev-parse HEAD 2>$null
        if ($LASTEXITCODE -ne 0 -or $revision -notmatch '^[0-9a-fA-F]{40}$') { return $unknown }
        $status = & $git -C $Repo status --porcelain 2>$null
        if ($LASTEXITCODE -ne 0) { return $unknown }
        return @{ sourceCommitAtLaunch = $revision; sourceDirtyAtLaunch = [bool]$status }
    } catch {
        return $unknown
    }
}
