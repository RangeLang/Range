# Gradient macOS Install Folder

This folder installs the Gradient command line tool.

GitHub releases also include `.pkg` installer artifacts for users who prefer
the standard macOS Installer flow:

- `gradient-macos-arm64.pkg`
- `gradient-macos-x64.pkg`

The shell installer exposes `gradient` and shared resources from `~/.gradient`. The
exposed paths are symlinks to a versioned Gradient-owned store under
`$HOME/.gradient/GradientCLI/<version>`.

## Contents

- `bin/gradient`: the Gradient CLI executable
- `share/gradient/GradientCore`: language core sources used by the CLI
- `share/gradient/Skills`: bundled Codex skills for Gradient onboarding
- `install.sh`: copies `bin/gradient` into your command line path
- `uninstall.sh`: removes the installed `gradient` executable and shared Gradient resources
- `INSTALL_MANIFEST.md`: describes what the installer changes
- `VERSION`: the release version packaged by GitHub Actions

## Install

```sh
./install.sh
```

By default, this exposes:

```text
$HOME/.gradient/bin/gradient
$HOME/.gradient/share/gradient/GradientCore
$HOME/.gradient/share/gradient/Skills
$HOME/.gradient/Packages
```

To install somewhere else:

```sh
GRADIENT_INSTALL_PREFIX="$HOME/.gradient" ./install.sh
```

That installs:

```text
$HOME/.gradient/bin/gradient
$HOME/.gradient/share/gradient/GradientCore
$HOME/.gradient/share/gradient/Skills
$HOME/.gradient/Packages
```

In all cases, the versioned payload is stored under:

```text
$HOME/.gradient/GradientCLI/<version>
```

## Verify

```sh
gradient version
```

## Uninstall

```sh
./uninstall.sh
```
