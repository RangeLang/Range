# Range Windows Install Folder

This folder installs the Range command line tool on Windows.

The PowerShell installer stores each release under `%USERPROFILE%\.range\releases\<version>`
and points `%USERPROFILE%\.range\current\<version>` at the active installed release.

## Contents

- `range.exe`: the Range CLI executable
- `RangeCore`: language core sources used by the CLI
- `install.ps1`: installs this release under `%USERPROFILE%\.range\releases`
- `VERSION`: the release version packaged by GitHub Actions

## Install

```powershell
.\install.ps1
```

To install somewhere else:

```powershell
.\install.ps1 -InstallPrefix "$HOME\.range"
```

Add `%USERPROFILE%\.range\current\<version>` to `Path` to use `range` from the shell.

## Verify

```powershell
range version
```
