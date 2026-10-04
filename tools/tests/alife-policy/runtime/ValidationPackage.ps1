function Read-ValidationPackage([string]$Engine) {
    $manifest = Join-Path (Split-Path -Parent $Engine) 'build.json'
    $build = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    if ($build.configuration -cne 'Release' -or $build.tracyEnabled -isnot [bool] -or $build.tracyEnabled) {
        throw 'Validation requires a Release package with tracyEnabled=false'
    }
    if ($build.sha256 -notmatch '^[0-9a-fA-F]{64}$' -or $build.sha256 -ine (Get-FileHash -LiteralPath $Engine -Algorithm SHA256).Hash) {
        throw 'Validation package executable hash does not match build.json'
    }
    return $build
}
