---
name: range-onboarding
description: Use when helping a user get started with an installed Range macOS package, explain where Range installs shared resources, set up a Package.range project, link or install project-local Range CLI versions, create .range/.scripts entries, update Range from GitHub releases, or troubleshoot first-run Range CLI usage.
---

# Range Onboarding

Use this skill for first-run setup, package installation questions, and project-local workflow questions after Range is installed.

## Installed Layout

The macOS package installs Range under a versioned payload and points
`current` at the active version:

```text
<prefix>/current -> versions/<version>
<prefix>/current/range
<prefix>/current/RangeCore
<prefix>/current/Skills
```

The shell installer default prefix is `~/.range`, so the CLI is normally:

```text
$HOME/.range/current/range
$HOME/.range/Packages
```

Downloaded machine packages live under:

```text
$HOME/.range/Packages
```

The `.lang.tar.gz` installer can use another writable prefix:

```sh
RANGE_INSTALL_PREFIX="$HOME/.range" ./install.sh
```

## First Checks

Run:

```sh
range version
range --help
```

If `range` is not found, check whether the install prefix's `bin` directory is on `PATH`.

## Project Setup

Create a project:

```sh
range create MyProject
```

Existing projects are recognized by `Package.range` at the project root.

## Project-Local CLI

Install the current macOS Range CLI into a package root:

```sh
range link .
```

This stores versioned CLI copies inside the project workspace:

```text
.range/versions/<version>/range
.range/current/range
.range/Links/range.package-link.json
```

Different CLI versions can coexist under `.range/versions`. The `.range/current`
path points to the selected project-local version.

## Project Scripts

Project scripts live under:

```text
.range/.scripts
```

Use:

```sh
range scripts create build
range scripts save deploy --content '#main { Logger.info("deploy") }'
range scripts save deploy --from ./deploy.range --force
range scripts list
```

## Updates

Update the installed CLI from the latest GitHub release:

```sh
range update
```

Update project modules:

```sh
range update .
```

Use `range version` to see the installed version and whether an update is available.

## Troubleshooting

- If `range update` prompts for a destination, prefer a writable prefix rather than adding random privilege prompts.
- If `RangeCore` is missing, inspect `<prefix>/current/RangeCore`.
- If bundled skills are missing, inspect `<prefix>/current/Skills`.
- If project-local commands feel stale, rerun `range link .` from the project root after updating Range.
