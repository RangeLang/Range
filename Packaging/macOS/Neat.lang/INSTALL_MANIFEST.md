# Install Manifest

Package: Neat CLI

This package installs one executable and the bundled NeatCore sources required
by the CLI:

```text
bin/neat -> /usr/local/bin/neat
share/neat/NeatCore -> /usr/local/share/neat/NeatCore
```

The install location can be changed with `NEAT_INSTALL_PREFIX`:

```sh
NEAT_INSTALL_PREFIX="$HOME/.local" ./install.sh
```

With that setting, the files are installed to:

```text
$HOME/.local/bin/neat
$HOME/.local/share/neat/NeatCore
```

The installer does not add login items, background services, launch agents, shell profile changes, or system extensions.

The uninstall script removes only the installed `neat` executable and bundled
NeatCore sources from the selected prefix.
