param(
    [string]$Version = "latest",
    [string]$Repository = $(if ($env:GRADIENT_REPOSITORY) { $env:GRADIENT_REPOSITORY } else { "georgegradient/Gradient" }),
    [string]$InstallDir = $(if ($env:GRADIENT_INSTALL_DIR) { $env:GRADIENT_INSTALL_DIR } else { Join-Path $HOME ".gradient\bin" })
)

$ErrorActionPreference = "Stop"

if ($Version -eq "-h" -or $Version -eq "--help") {
    Write-Host "Usage: ./install-gradient-release.ps1 [-Version latest|vX.Y.Z] [-Repository owner/repo] [-InstallDir path]"
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

$artifact = "gradient-windows-$arch"
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
    Copy-Item -Path (Join-Path $tmp "$artifact\gradient.exe") -Destination (Join-Path $InstallDir "gradient.exe") -Force

    Write-Host "Installed gradient to $(Join-Path $InstallDir "gradient.exe")"
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (($userPath -split ";") -notcontains $InstallDir) {
        Write-Host "Add this directory to your user PATH:"
        Write-Host "  $InstallDir"
    }
} finally {
    Remove-Item -Recurse -Force $tmp
}
