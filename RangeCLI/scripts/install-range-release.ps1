param(
    [string]$Version = "latest",
    [string]$Repository = $(if ($env:RANGE_REPOSITORY) { $env:RANGE_REPOSITORY } else { "georgetchelidze/Range" }),
    [string]$InstallPrefix = $(if ($env:RANGE_INSTALL_PREFIX) { $env:RANGE_INSTALL_PREFIX } else { Join-Path $HOME ".range" })
)

$ErrorActionPreference = "Stop"

if ($Version -eq "-h" -or $Version -eq "--help") {
    Write-Host "Usage: ./install-range-release.ps1 [-Version latest|vX.Y.Z] [-Repository owner/repo] [-InstallPrefix path]"
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

    $resolvedVersion = if ($Version.StartsWith("v")) { $Version.Substring(1) } else { $Version }
    if ($resolvedVersion -eq "latest") {
        $resolvedVersion = "unknown"
    }
    $versionRoot = Join-Path $InstallPrefix "versions\$resolvedVersion"
    New-Item -ItemType Directory -Force -Path $versionRoot | Out-Null
    Copy-Item -Path (Join-Path $tmp "$artifact\range.exe") -Destination (Join-Path $versionRoot "range.exe") -Force

    $current = Join-Path $InstallPrefix "current"
    if (Test-Path $current) {
        Remove-Item -Recurse -Force $current
    }
    New-Item -ItemType SymbolicLink -Path $current -Target $versionRoot | Out-Null

    Write-Host "Installed range to $(Join-Path $current "range.exe")"
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (($userPath -split ";") -notcontains $current) {
        Write-Host "Add this directory to your user PATH:"
        Write-Host "  $current"
    }
} finally {
    Remove-Item -Recurse -Force $tmp
}
