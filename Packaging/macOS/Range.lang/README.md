# Range macOS Install Folder

This folder installs the Range command line tool.

GitHub releases also include `.pkg` installer artifacts for users who prefer
the standard macOS Installer flow:

- `range-macos-arm64.pkg`
- `range-macos-x64.pkg`

The shell installer exposes `range` and shared resources from `~/.range`. The
exposed paths are symlinks to a versioned Range-owned store under
`$HOME/.range/RangeCLI/<version>`.

## Contents

- `bin/range`: the Range CLI executable
- `share/range/RangeCore`: language core sources used by the CLI
- `share/range/Skills`: bundled Codex skills for Range onboarding
- `install.sh`: copies `bin/range` into your command line path
- `uninstall.sh`: removes the installed `range` executable and shared Range resources
- `INSTALL_MANIFEST.md`: describes what the installer changes
- `VERSION`: the release version packaged by GitHub Actions

## Install

```sh
./install.sh
```

By default, this exposes:

```text
$HOME/.range/bin/range
$HOME/.range/share/range/RangeCore
$HOME/.range/share/range/Skills
$HOME/.range/Packages
```

To install somewhere else:

```sh
RANGE_INSTALL_PREFIX="$HOME/.range" ./install.sh
```

That installs:

```text
$HOME/.range/bin/range
$HOME/.range/share/range/RangeCore
$HOME/.range/share/range/Skills
$HOME/.range/Packages
```

In all cases, the versioned payload is stored under:

```text
$HOME/.range/RangeCLI/<version>
```

## Verify

```sh
range version
```

## Uninstall

```sh
./uninstall.sh
```
