param(
    [Parameter(Mandatory)][string]$ToolRoot,
    [string]$CMake = 'cmake'
)
$ErrorActionPreference = 'Stop'
$revision = '4a5a21cdb08c3b554bf1857b4f2f33d7f7db0207'
$repo = (Resolve-Path "$PSScriptRoot/../..").Path
$source = Join-Path $ToolRoot 'source'
function Invoke-Checked([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed: $LASTEXITCODE" }
}
if (!(Test-Path $source)) {
    Invoke-Checked git @('clone', '--filter=blob:none', 'https://github.com/wolfpld/tracy.git', $source)
    Invoke-Checked git @('-C', $source, 'checkout', '--detach', $revision)
}
if ((& git -C $source rev-parse HEAD) -ne $revision) { throw 'Existing Tracy checkout has a different revision; use a new ToolRoot.' }
if (& git -C $source status --porcelain --untracked-files=no) { throw 'Tracy checkout has tracked changes; use a clean source checkout.' }
# Version numbers alone are insufficient for this unreleased OGSR client.
foreach ($header in @('TracyVersion.hpp', 'TracyProtocol.hpp', 'TracyQueue.hpp')) {
    $embedded = "$repo/3rd_party/Src/tracy/public/common/$header"
    $upstream = "$source/public/common/$header"
    if ((Get-Content -Raw $embedded).Replace("`r`n", "`n") -cne (Get-Content -Raw $upstream).Replace("`r`n", "`n")) {
        throw "Embedded Tracy differs in $header; review compatibility before building."
    }
}
foreach ($tool in @('capture', 'csvexport')) {
    Invoke-Checked $CMake @('-S', "$source/$tool", '-B', "$source/build-$tool", '-G', 'Visual Studio 17 2022', '-A', 'x64', "-DCPM_SOURCE_CACHE=$source/build-capture/.cpm-cache")
    Invoke-Checked $CMake @('--build', "$source/build-$tool", '--config', 'Release', '--parallel', '2')
}
$bin = New-Item -ItemType Directory -Force (Join-Path $ToolRoot 'bin')
foreach ($tool in @('capture', 'csvexport')) {
    Copy-Item "$source/build-$tool/Release/tracy-$tool.exe" $bin.FullName
}
Invoke-Checked $CMake @('-S', $PSScriptRoot, '-B', "$ToolRoot/build-summary", '-G', 'Visual Studio 17 2022', '-A', 'x64', "-DTRACY_SOURCE=$source", "-DCPM_SOURCE_CACHE=$source/build-capture/.cpm-cache")
Invoke-Checked $CMake @('--build', "$ToolRoot/build-summary", '--config', 'Release', '--target', 'ogsr-trace-summary', '--parallel', '2')
Copy-Item "$ToolRoot/build-summary/Release/ogsr-trace-summary.exe" $bin.FullName
@{ source = 'https://github.com/wolfpld/tracy'; revision = $revision; protocol = 72; version = '0.11.2' } |
    ConvertTo-Json | Set-Content "$ToolRoot/tools.json" -Encoding utf8
