# Install Manifest

Package: Gradient CLI

This package stores one executable, the bundled GradientCore sources required
by the CLI, and bundled Codex skills in a versioned Gradient-owned directory:

```text
$HOME/.gradient/GradientCLI/<version>
```

The selected prefix exposes symlinks:

```text
$HOME/.gradient/bin/gradient -> $HOME/.gradient/GradientCLI/<version>/bin/gradient
$HOME/.gradient/share/gradient/GradientCore -> $HOME/.gradient/GradientCLI/<version>/share/gradient/GradientCore
$HOME/.gradient/share/gradient/Skills -> $HOME/.gradient/GradientCLI/<version>/share/gradient/Skills
```

The installer also creates the machine package store:

```text
$HOME/.gradient/Packages
```

The install location can be changed with `GRADIENT_INSTALL_PREFIX`:

```sh
GRADIENT_INSTALL_PREFIX="$HOME/.gradient" ./install.sh
```

With that setting, the visible symlinks are:

```text
$HOME/.gradient/bin/gradient
$HOME/.gradient/share/gradient/GradientCore
$HOME/.gradient/share/gradient/Skills
$HOME/.gradient/Packages
```

The installer does not add login items, background services, launch agents, shell profile changes, or system extensions.

The uninstall script removes only the installed `gradient` executable and bundled
shared Gradient resources from the selected prefix. It does not remove
`$HOME/.gradient/Packages`.
