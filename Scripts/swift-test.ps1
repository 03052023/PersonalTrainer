# Roda `swift test` do TrainerCore no Windows.
# O toolchain Swift para Windows precisa do link.exe e dos headers do MSVC/Windows SDK,
# que só ficam disponíveis dentro do "Developer PowerShell" do Visual Studio.
# Uso:  powershell -ExecutionPolicy Bypass -File Scripts/swift-test.ps1 [-Build] [-Filter <regex>]
param(
    [switch]$Build,
    [string]$Filter
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$package = Join-Path $repo 'Packages\TrainerCore'

$installerDir = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer"
$vswhere = Join-Path $installerDir 'vswhere.exe'
if (-not (Test-Path $vswhere)) { throw "Visual Studio não encontrado (vswhere ausente). Instale VS 2022 Build Tools com 'Desktop development with C++'." }
$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vsPath) { throw "Nenhuma instalação do Visual Studio com MSVC x64 encontrada." }

# Launch-VsDevShell.ps1 chama vswhere.exe pelo nome; garante que ele esteja no PATH.
$env:Path = "$installerDir;$env:Path"
$devShell = Join-Path $vsPath 'Common7\Tools\Launch-VsDevShell.ps1'
& $devShell -Arch amd64 -HostArch amd64 -SkipAutomaticLocation | Out-Null

# O instalador do Swift grava SDKROOT e PATH como variáveis de usuário; sessões abertas
# antes da instalação (ou shells não interativos) podem não enxergá-las. Descobrimos tudo aqui.
$swiftRoot = Join-Path $env:LOCALAPPDATA 'Programs\Swift'
$swift = Get-ChildItem (Join-Path $swiftRoot 'Toolchains') -Recurse -Filter swift.exe -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1
if (-not $swift) { throw "swift.exe não encontrado em $swiftRoot\Toolchains." }
$runtimeBin = Get-ChildItem (Join-Path $swiftRoot 'Runtimes') -Recurse -Depth 3 -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq 'bin' } | Sort-Object FullName -Descending | Select-Object -First 1
$sdk = Get-ChildItem (Join-Path $swiftRoot 'Platforms') -Recurse -Depth 5 -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq 'Windows.sdk' } | Sort-Object FullName -Descending | Select-Object -First 1
if (-not $sdk) { throw "Windows.sdk do Swift não encontrado em $swiftRoot\Platforms." }

$env:SDKROOT = $sdk.FullName
$env:Path = "$($swift.DirectoryName);$(if ($runtimeBin) { $runtimeBin.FullName + ';' })$env:Path"

Push-Location $package
try {
    & $swift.FullName --version
    if ($Build) {
        & $swift.FullName build
    } elseif ($Filter) {
        & $swift.FullName test --filter $Filter
    } else {
        & $swift.FullName test
    }
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
