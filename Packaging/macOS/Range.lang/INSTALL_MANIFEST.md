# Install Manifest

Package: Range CLI

This package stores one executable, the bundled RangeCore sources required
by the CLI, and bundled Codex skills in a versioned Range-owned directory:

```text
$HOME/.range/RangeCLI/<version>
```

The selected prefix exposes symlinks:

```text
$HOME/.range/bin/range -> $HOME/.range/RangeCLI/<version>/bin/range
$HOME/.range/share/range/RangeCore -> $HOME/.range/RangeCLI/<version>/share/range/RangeCore
$HOME/.range/share/range/Skills -> $HOME/.range/RangeCLI/<version>/share/range/Skills
```

The installer also creates the machine package store:

```text
$HOME/.range/Packages
```

The install location can be changed with `RANGE_INSTALL_PREFIX`:

```sh
RANGE_INSTALL_PREFIX="$HOME/.range" ./install.sh
```

With that setting, the visible symlinks are:

```text
$HOME/.range/bin/range
$HOME/.range/share/range/RangeCore
$HOME/.range/share/range/Skills
$HOME/.range/Packages
```

The installer does not add login items, background services, launch agents, shell profile changes, or system extensions.

The uninstall script removes only the installed `range` executable and bundled
shared Range resources from the selected prefix. It does not remove
`$HOME/.range/Packages`.
