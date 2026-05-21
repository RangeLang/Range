# Install Manifest

Package: Range CLI

This package stores one executable, the bundled RangeCore sources required by
the CLI, and bundled Codex skills in a versioned Range-owned directory:

```text
$HOME/.range/releases/<version>
```

The selected prefix exposes one active-install symlink:

```text
$HOME/.range/current/<version> -> ../releases/<version>
```

The active release contains:

```text
$HOME/.range/current/<version>/range
$HOME/.range/current/<version>/RangeCore
$HOME/.range/current/<version>/Skills
$HOME/.range/current/<version>/VERSION
```

The installer also creates machine stores:

```text
$HOME/.range/Packages
$HOME/.range/Projects
```

The install location can be changed with `RANGE_INSTALL_PREFIX`:

```sh
RANGE_INSTALL_PREFIX="$HOME/.range" ./install.sh
```

The installer does not add login items, background services, launch agents,
shell profile changes, or system extensions.

The uninstall script removes only the active `current/<version>` symlink from
the selected prefix. It does not remove installed releases, `$HOME/.range/Packages`, or
`$HOME/.range/Projects`.
