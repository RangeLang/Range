# Neat macOS Install Folder

This folder installs the Neat command line tool.

GitHub releases also include `.pkg` installer artifacts for users who prefer
the standard macOS Installer flow:

- `neat-macos-arm64.pkg`
- `neat-macos-x64.pkg`

Those packages install `neat` to `/usr/local/bin/neat`.

## Contents

- `bin/neat`: the Neat CLI executable
- `install.sh`: copies `bin/neat` into your command line path
- `uninstall.sh`: removes the installed `neat` executable
- `INSTALL_MANIFEST.md`: describes what the installer changes
- `VERSION`: the release version packaged by GitHub Actions

## Install

```sh
./install.sh
```

By default, this installs:

```text
/usr/local/bin/neat
```

To install somewhere else:

```sh
NEAT_INSTALL_PREFIX="$HOME/.local" ./install.sh
```

That installs:

```text
$HOME/.local/bin/neat
```

## Verify

```sh
neat version
```

## Uninstall

```sh
./uninstall.sh
```
