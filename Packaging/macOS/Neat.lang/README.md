# Neat macOS Install Folder

This folder installs the Neat command line tool.

GitHub releases also include `.pkg` installer artifacts for users who prefer
the standard macOS Installer flow:

- `neat-macos-arm64.pkg`
- `neat-macos-x64.pkg`

Those packages expose `neat` at `/usr/local/bin/neat`, NeatCore at
`/usr/local/share/neat/NeatCore`, and bundled Codex skills at
`/usr/local/share/neat/Skills`. The exposed paths are symlinks to a
versioned Neat-owned store under `$HOME/.neat/NeatCLI/<version>`.

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

When `/usr/local` is writable, this exposes:

```text
/usr/local/bin/neat
/usr/local/share/neat/NeatCore
/usr/local/share/neat/Skills
```

When `/usr/local` is not writable, the shell installer defaults to:

```text
$HOME/.local/bin/neat
$HOME/.local/share/neat/NeatCore
$HOME/.local/share/neat/Skills
```

To install somewhere else:

```sh
NEAT_INSTALL_PREFIX="$HOME/.local" ./install.sh
```

That installs:

```text
$HOME/.local/bin/neat
$HOME/.local/share/neat/NeatCore
$HOME/.local/share/neat/Skills
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
