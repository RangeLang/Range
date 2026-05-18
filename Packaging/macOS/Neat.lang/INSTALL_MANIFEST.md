# Install Manifest

Package: Neat CLI

This package stores one executable, the bundled NeatCore sources required
by the CLI, and bundled Codex skills in a versioned Neat-owned directory:

```text
$HOME/.neat/NeatCLI/<version>
```

The selected prefix exposes symlinks:

```text
/usr/local/bin/neat -> $HOME/.neat/NeatCLI/<version>/bin/neat
/usr/local/share/neat/NeatCore -> $HOME/.neat/NeatCLI/<version>/share/neat/NeatCore
/usr/local/share/neat/Skills -> $HOME/.neat/NeatCLI/<version>/share/neat/Skills
```

The install location can be changed with `NEAT_INSTALL_PREFIX`:

```sh
NEAT_INSTALL_PREFIX="$HOME/.local" ./install.sh
```

With that setting, the visible symlinks are:

```text
$HOME/.local/bin/neat
$HOME/.local/share/neat/NeatCore
$HOME/.local/share/neat/Skills
```

The installer does not add login items, background services, launch agents, shell profile changes, or system extensions.

The uninstall script removes only the installed `neat` executable and bundled
shared Neat resources from the selected prefix.
