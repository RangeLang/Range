# Install Manifest

Package: Neat CLI

This package installs one executable:

```text
bin/neat -> /usr/local/bin/neat
```

The install location can be changed with `NEAT_INSTALL_PREFIX`:

```sh
NEAT_INSTALL_PREFIX="$HOME/.local" ./install.sh
```

With that setting, the executable is installed to:

```text
$HOME/.local/bin/neat
```

The installer does not add login items, background services, launch agents, shell profile changes, or system extensions.

The uninstall script removes only the installed `neat` executable from the selected prefix.
