# Git Integration Delay

Git integration is being delayed until Neat's package and install surfaces are clearer.

## Before

```text
download Neat
  requires Git knowledge
  depends on repository shape
  mixes install, source checkout, and package metadata
```

## After

```text
download Neat
  gets an inspectable install package
  installs the neat CLI
  can create and run projects without Git

package publishing
  can still use Git tags and remotes
  stays separate from first install
```

## Reason

The old path made Git feel like part of installing the language.

That is the wrong first shape. A user should be able to download Neat, inspect what will be installed, install the CLI, and run `neat create` without understanding remotes, tags, or repository layout.

Git still matters for package publishing, version tags, and source remotes. Delaying deeper Git integration keeps those responsibilities out of the installer and gives the package graph room to define what a remote means in Neat terms before the CLI automates it.
