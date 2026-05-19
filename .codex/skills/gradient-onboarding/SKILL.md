---
name: gradient-onboarding
description: Use when helping a user get started with an installed Gradient macOS package, explain where Gradient installs shared resources, set up a Package.gradient project, link or install project-local Gradient CLI versions, create .gradient/.scripts entries, update Gradient from GitHub releases, or troubleshoot first-run Gradient CLI usage.
---

# Gradient Onboarding

Use this skill for first-run setup, package installation questions, and project-local workflow questions after Gradient is installed.

## Installed Layout

The macOS package installs shared Gradient resources under the selected prefix:

```text
<prefix>/bin/gradient
<prefix>/share/gradient/GradientCore
<prefix>/share/gradient/Skills
```

The shell installer default prefix is `~/.gradient`, so the CLI is normally:

```text
$HOME/.gradient/bin/gradient
$HOME/.gradient/Packages
```

Downloaded machine packages live under:

```text
$HOME/.gradient/Packages
```

The `.lang.tar.gz` installer can use another writable prefix:

```sh
GRADIENT_INSTALL_PREFIX="$HOME/.gradient" ./install.sh
```

## First Checks

Run:

```sh
gradient version
gradient --help
```

If `gradient` is not found, check whether the install prefix's `bin` directory is on `PATH`.

## Project Setup

Create a project:

```sh
gradient create MyProject
```

Existing projects are recognized by `Package.gradient` at the project root.

## Project-Local CLI

Install the current macOS Gradient CLI into a package root:

```sh
gradient link .
```

This stores versioned CLI copies inside the project workspace:

```text
.gradient/GradientCLI/<version>/bin/gradient
.gradient/bin/gradient
.gradient/Links/gradient.package-link.json
```

Different CLI versions can coexist under `.gradient/GradientCLI`. The `.gradient/bin/gradient` path points to the selected project-local version.

## Project Scripts

Project scripts live under:

```text
.gradient/.scripts
```

Use:

```sh
gradient scripts create build
gradient scripts save deploy --content '#main { Logger.info("deploy") }'
gradient scripts save deploy --from ./deploy.gradient --force
gradient scripts list
```

## Updates

Update the installed CLI from the latest GitHub release:

```sh
gradient update
```

Update project modules:

```sh
gradient update .
```

Use `gradient version` to see the installed version and whether an update is available.

## Troubleshooting

- If `gradient update` prompts for a destination, prefer a writable prefix rather than adding random privilege prompts.
- If `GradientCore` is missing, inspect `<prefix>/share/gradient/GradientCore`.
- If bundled skills are missing, inspect `<prefix>/share/gradient/Skills`.
- If project-local commands feel stale, rerun `gradient link .` from the project root after updating Gradient.
