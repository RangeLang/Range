param(
    [string]$Version = "latest",
    [string]$Repository = $(if ($env:RANGE_REPOSITORY) { $env:RANGE_REPOSITORY } else { "georgerange/Range" }),
    [string]$InstallDir = $(if ($env:RANGE_INSTALL_DIR) { $env:RANGE_INSTALL_DIR } else { Join-Path $HOME ".range\bin" })
)

$ErrorActionPreference = "Stop"

if ($Version -eq "-h" -or $Version -eq "--help") {
    Write-Host "Usage: ./install-range-release.ps1 [-Version latest|vX.Y.Z] [-Repository owner/repo] [-InstallDir path]"
    exit 0
}

$arch = switch ($env:PROCESSOR_ARCHITECTURE) {
    "AMD64" { "x64" }
    "ARM64" { "arm64" }
    default { throw "Unsupported architecture: $env:PROCESSOR_ARCHITECTURE" }
}

if ($arch -ne "x64") {
    throw "No Windows $arch release artifact is published yet."
}

$artifact = "range-windows-$arch"
$archive = "$artifact.zip"
if ($Version -eq "latest") {
    $url = "https://github.com/$Repository/releases/latest/download/$archive"
} else {
    $url = "https://github.com/$Repository/releases/download/$Version/$archive"
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
    $zipPath = Join-Path $tmp $archive
    Write-Host "Downloading $url"
    Invoke-WebRequest -Uri $url -OutFile $zipPath
    Expand-Archive -Path $zipPath -DestinationPath $tmp -Force

    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    Copy-Item -Path (Join-Path $tmp "$artifact\range.exe") -Destination (Join-Path $InstallDir "range.exe") -Force

    Write-Host "Installed range to $(Join-Path $InstallDir "range.exe")"
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (($userPath -split ";") -notcontains $InstallDir) {
        Write-Host "Add this directory to your user PATH:"
        Write-Host "  $InstallDir"
    }
} finally {
    Remove-Item -Recurse -Force $tmp
}
