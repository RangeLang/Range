# Range macOS Install Folder

This folder installs the Range command line tool.

The shell installer stores each release under `~/.range/versions/<version>` and
points `~/.range/current` at the active installed release.

## Contents

- `range`: the Range CLI executable
- `RangeCore`: language core sources used by the CLI
- `Skills`: bundled Codex skills for Range onboarding
- `install.sh`: installs this release under `~/.range/versions`
- `uninstall.sh`: removes the active `~/.range/current` selection
- `INSTALL_MANIFEST.md`: describes what the installer changes
- `VERSION`: the release version packaged by GitHub Actions

## Install

```sh
./install.sh
```

By default, this creates:

```text
$HOME/.range/current -> versions/<version>
$HOME/.range/versions/<version>/range
$HOME/.range/versions/<version>/RangeCore
$HOME/.range/versions/<version>/Skills
$HOME/.range/Packages
$HOME/.range/Projects
```

To install somewhere else:

```sh
RANGE_INSTALL_PREFIX="$HOME/.range" ./install.sh
```

That installs the same layout under the selected prefix:

```text
$HOME/.range/current/range
```

Add `~/.range/current` to `PATH` to use `range` from the shell.

## Verify

```sh
range version
```

## Uninstall

```sh
./uninstall.sh
```
