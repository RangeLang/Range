# Neat macOS Install Folder

This folder installs the Neat command line tool.

GitHub releases also include `.pkg` installer artifacts for users who prefer
the standard macOS Installer flow:

- `neat-macos-arm64.pkg`
- `neat-macos-x64.pkg`

The shell installer exposes `neat` and shared resources from `~/.neat`. The
exposed paths are symlinks to a versioned Neat-owned store under
`$HOME/.neat/NeatCLI/<version>`.

## Contents

- `bin/neat`: the Neat CLI executable
- `share/neat/NeatCore`: language core sources used by the CLI
- `share/neat/Skills`: bundled Codex skills for Neat onboarding
- `install.sh`: copies `bin/neat` into your command line path
- `uninstall.sh`: removes the installed `neat` executable and shared Neat resources
- `INSTALL_MANIFEST.md`: describes what the installer changes
- `VERSION`: the release version packaged by GitHub Actions

## Install

```sh
./install.sh
```

By default, this exposes:

```text
$HOME/.neat/bin/neat
$HOME/.neat/share/neat/NeatCore
$HOME/.neat/share/neat/Skills
$HOME/.neat/Packages
```

To install somewhere else:

```sh
NEAT_INSTALL_PREFIX="$HOME/.neat" ./install.sh
```

That installs:

```text
$HOME/.neat/bin/neat
$HOME/.neat/share/neat/NeatCore
$HOME/.neat/share/neat/Skills
$HOME/.neat/Packages
```

In all cases, the versioned payload is stored under:

```text
$HOME/.neat/NeatCLI/<version>
```

## Verify

```sh
neat version
```

## Uninstall

```sh
./uninstall.sh
```
