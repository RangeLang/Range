# Install Manifest

Package: Neat CLI

This package installs one executable, the bundled NeatCore sources required
by the CLI, and bundled Codex skills:

```text
bin/neat -> /usr/local/bin/neat
share/neat/NeatCore -> /usr/local/share/neat/NeatCore
share/neat/Skills -> /usr/local/share/neat/Skills
```

The install location can be changed with `NEAT_INSTALL_PREFIX`:

```sh
NEAT_INSTALL_PREFIX="$HOME/.local" ./install.sh
```

With that setting, the files are installed to:

```text
$HOME/.local/bin/neat
$HOME/.local/share/neat/NeatCore
$HOME/.local/share/neat/Skills
```

The installer does not add login items, background services, launch agents, shell profile changes, or system extensions.

The uninstall script removes only the installed `neat` executable and bundled
shared Neat resources from the selected prefix.
