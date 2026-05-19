# Install Manifest

Package: Neat CLI

This package stores one executable, the bundled NeatCore sources required
by the CLI, and bundled Codex skills in a versioned Neat-owned directory:

```text
$HOME/.neat/NeatCLI/<version>
```

The selected prefix exposes symlinks:

```text
$HOME/.neat/bin/neat -> $HOME/.neat/NeatCLI/<version>/bin/neat
$HOME/.neat/share/neat/NeatCore -> $HOME/.neat/NeatCLI/<version>/share/neat/NeatCore
$HOME/.neat/share/neat/Skills -> $HOME/.neat/NeatCLI/<version>/share/neat/Skills
```

The installer also creates the machine package store:

```text
$HOME/.neat/Packages
```

The install location can be changed with `NEAT_INSTALL_PREFIX`:

```sh
NEAT_INSTALL_PREFIX="$HOME/.neat" ./install.sh
```

With that setting, the visible symlinks are:

```text
$HOME/.neat/bin/neat
$HOME/.neat/share/neat/NeatCore
$HOME/.neat/share/neat/Skills
$HOME/.neat/Packages
```

The installer does not add login items, background services, launch agents, shell profile changes, or system extensions.

The uninstall script removes only the installed `neat` executable and bundled
shared Neat resources from the selected prefix. It does not remove
`$HOME/.neat/Packages`.
