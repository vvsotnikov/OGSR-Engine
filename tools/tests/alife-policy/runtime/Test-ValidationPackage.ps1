$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/ValidationPackage.ps1"
$root = Join-Path ([IO.Path]::GetTempPath()) ('ogsr-package-' + [guid]::NewGuid())
New-Item -ItemType Directory $root | Out-Null
try {
    $engine = Join-Path $root 'xrEngine.exe'
    Set-Content -LiteralPath $engine 'fixture'
    $validHash = (Get-FileHash -LiteralPath $engine -Algorithm SHA256).Hash
    foreach ($case in @(
        @{configuration='Release'; tracyEnabled=$false; sha256=$validHash; valid=$true},
        @{configuration='ReleaseTracyProfiler'; tracyEnabled=$true; sha256=$validHash; valid=$false},
        @{configuration='Debug'; tracyEnabled=$false; sha256=$validHash; valid=$false},
        @{configuration='Release'; tracyEnabled='false'; sha256=$validHash; valid=$false},
        @{configuration='Release'; sha256=$validHash; valid=$false},
        @{configuration='Release'; tracyEnabled=$false; sha256=('0' * 64); valid=$false}
    )) {
        $case | ConvertTo-Json | Set-Content (Join-Path $root 'build.json')
        $accepted = $false
        try { $null = Read-ValidationPackage $engine; $accepted = $true } catch { }
        if ($accepted -ne $case.valid) { throw 'Manifest acceptance mismatch' }
    }
    @{configuration='Debug'; tracyEnabled=$false; sha256=$validHash} | ConvertTo-Json | Set-Content (Join-Path $root 'build.json')
    $null = Read-ValidationPackage $engine -Configuration Debug
} finally {
    # Only exact files created by this fixture are removed; no recursive cleanup.
    Remove-Item -LiteralPath (Join-Path $root 'xrEngine.exe'), (Join-Path $root 'build.json') -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $root
}
