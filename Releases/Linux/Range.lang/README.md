# Range Linux Install Folder

This folder installs the Range command line tool.

The shell installer stores each release under `~/.range/releases/<version>` and
points `~/.range/current/<version>` at the active installed release.

## Contents

- `range`: the CLI executable
- `RangeCore`: language core sources used by the CLI
- `install.sh`: installs this release under `~/.range/releases`
- `uninstall.sh`: removes the active `~/.range/current/<version>` selection
- `INSTALL_MANIFEST.md`: describes what the installer changes
- `VERSION`: the release version packaged by GitHub Actions

## Install

```sh
./install.sh
```

By default, this creates:

```text
$HOME/.range/current/<version> -> ../releases/<version>
$HOME/.range/releases/<version>/range
$HOME/.range/releases/<version>/RangeCore
$HOME/.range/Packages
$HOME/.range/Projects
```

To install somewhere else:

```sh
RANGE_INSTALL_PREFIX="$HOME/.range" ./install.sh
```

That installs the same layout under the selected prefix:

```text
$HOME/.range/current/<version>/range
```

Add `~/.range/current/<version>` to `PATH` to use `range` from the shell.

## Verify

```sh
range version
```

## Uninstall

```sh
./uninstall.sh
```
