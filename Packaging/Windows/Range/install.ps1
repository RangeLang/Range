param(
    [string]$InstallPrefix = $(if ($env:RANGE_INSTALL_PREFIX) { $env:RANGE_INSTALL_PREFIX } else { Join-Path $HOME ".range" })
)

$ErrorActionPreference = "Stop"

$packageRoot = $PSScriptRoot
$binary = Join-Path $packageRoot "range.exe"
$coreSources = Join-Path $packageRoot "RangeCore"
$versionFile = Join-Path $packageRoot "VERSION"
$version = "unknown"

if (Test-Path $versionFile) {
    $version = (Get-Content -Raw $versionFile).Trim()
}

$storeRoot = Join-Path $InstallPrefix "releases"
$currentRoot = Join-Path $InstallPrefix "current"
$packagesDir = Join-Path $InstallPrefix "Packages"
$projectsDir = Join-Path $InstallPrefix "Projects"
$payloadDir = Join-Path $storeRoot $version
$currentVersion = Join-Path $currentRoot $version

if (-not (Test-Path $binary)) {
    throw "Missing executable: $binary"
}

if (-not (Test-Path $coreSources)) {
    throw "Missing RangeCore sources: $coreSources"
}

Write-Host "Range CLI installer"
Write-Host ""
Write-Host "Will install Range $version"
Write-Host "stored in:"
Write-Host "  $payloadDir"
Write-Host "active install:"
Write-Host "  $currentVersion"
Write-Host ""

if ($env:RANGE_INSTALL_ASSUME_YES -ne "true") {
    $answer = Read-Host "Continue? [y/N]"
    if ($answer -notin @("y", "Y", "yes", "YES")) {
        Write-Host "Cancelled."
        exit 0
    }
}

New-Item -ItemType Directory -Force -Path $InstallPrefix, $storeRoot, $currentRoot, $packagesDir, $projectsDir | Out-Null

if (Test-Path $payloadDir) {
    Remove-Item -Recurse -Force $payloadDir
}
New-Item -ItemType Directory -Force -Path $payloadDir | Out-Null
Copy-Item -Path (Join-Path $packageRoot "*") -Destination $payloadDir -Recurse -Force

if (Test-Path $currentVersion) {
    Remove-Item -Recurse -Force $currentVersion
}

try {
    New-Item -ItemType Junction -Path $currentVersion -Target $payloadDir | Out-Null
} catch {
    New-Item -ItemType SymbolicLink -Path $currentVersion -Target $payloadDir | Out-Null
}

Write-Host ""
Write-Host "Installed $(Join-Path $currentVersion "range.exe")"
Write-Host "Run: range version"
