param(
    [Parameter(Mandatory)][string]$ToolRoot,
    [string]$CMake = 'cmake',
    [string]$Generator = 'Visual Studio 17 2022',
    [ValidateRange(1,128)][int]$Jobs = 2
)
$ErrorActionPreference = 'Stop'
$ToolRoot = [IO.Path]::GetFullPath($ToolRoot)
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
Invoke-Checked $CMake @('--fresh', '-S', "$source/capture", '-B', "$ToolRoot/build-capture", '-G', $Generator, '-A', 'x64', "-DCPM_SOURCE_CACHE=$ToolRoot/.cpm-cache")
Invoke-Checked $CMake @('--build', "$ToolRoot/build-capture", '--config', 'Release', '--parallel', $Jobs)
$bin = New-Item -ItemType Directory -Force (Join-Path $ToolRoot 'bin')
Copy-Item "$ToolRoot/build-capture/Release/tracy-capture.exe" $bin.FullName
Invoke-Checked $CMake @('--fresh', '-S', $PSScriptRoot, '-B', "$ToolRoot/build-export", '-G', $Generator, '-A', 'x64', "-DTRACY_SOURCE=$source", "-DCPM_SOURCE_CACHE=$ToolRoot/.cpm-cache")
Invoke-Checked $CMake @('--build', "$ToolRoot/build-export", '--config', 'Release', '--target', 'ogsr-trace-export', '--parallel', $Jobs)
Copy-Item "$ToolRoot/build-export/Release/ogsr-trace-export.exe" $bin.FullName
@{ source = 'https://github.com/wolfpld/tracy'; revision = $revision; compatibilityHeaders = @('TracyVersion.hpp', 'TracyProtocol.hpp', 'TracyQueue.hpp') } |
    ConvertTo-Json | Set-Content (Join-Path $bin.FullName 'tools.json') -Encoding utf8
