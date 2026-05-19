---
name: neat-onboarding
description: Use when helping a user get started with an installed Neat macOS package, explain where Neat installs shared resources, set up a Package.neat project, link or install project-local Neat CLI versions, create .neat/.scripts entries, update Neat from GitHub releases, or troubleshoot first-run Neat CLI usage.
---

# Neat Onboarding

Use this skill for first-run setup, package installation questions, and project-local workflow questions after Neat is installed.

## Installed Layout

The macOS package installs shared Neat resources under the selected prefix:

```text
<prefix>/bin/neat
<prefix>/share/neat/NeatCore
<prefix>/share/neat/Skills
```

The shell installer default prefix is `~/.neat`, so the CLI is normally:

```text
$HOME/.neat/bin/neat
```

The `.lang.tar.gz` installer can use another writable prefix:

```sh
NEAT_INSTALL_PREFIX="$HOME/.neat" ./install.sh
```

## First Checks

Run:

```sh
neat version
neat --help
```

If `neat` is not found, check whether the install prefix's `bin` directory is on `PATH`.

## Project Setup

Create a project:

```sh
neat create MyProject
```

Existing projects are recognized by `Package.neat` at the project root.

## Project-Local CLI

Install the current macOS Neat CLI into a package root:

```sh
neat link .
```

This stores versioned CLI copies inside the project workspace:

```text
.neat/NeatCLI/<version>/bin/neat
.neat/bin/neat
.neat/Links/neat.package-link.json
```

Different CLI versions can coexist under `.neat/NeatCLI`. The `.neat/bin/neat` path points to the selected project-local version.

## Project Scripts

Project scripts live under:

```text
.neat/.scripts
```

Use:

```sh
neat scripts create build
neat scripts save deploy --content '#main { Logger.info("deploy") }'
neat scripts save deploy --from ./deploy.neat --force
neat scripts list
```

## Updates

Update the installed CLI from the latest GitHub release:

```sh
neat update
```

Update project modules:

```sh
neat update .
```

Use `neat version` to see the installed version and whether an update is available.

## Troubleshooting

- If `neat update` prompts for a destination, prefer a writable prefix rather than adding random privilege prompts.
- If `NeatCore` is missing, inspect `<prefix>/share/neat/NeatCore`.
- If bundled skills are missing, inspect `<prefix>/share/neat/Skills`.
- If project-local commands feel stale, rerun `neat link .` from the project root after updating Neat.
