---
name: range-onboarding
description: Use when helping a user get started with an installed Range macOS package, explain where Range installs shared resources, set up a Package.range project, link or install project-local Range CLI releases, create .range/.scripts entries, update Range from GitHub releases, or troubleshoot first-run Range CLI usage.
---

# Range Onboarding

Use this skill for first-run setup, package installation questions, and project-local workflow questions after Range is installed.

## Workflow

1. Check whether the user is asking about a global install, a project-local CLI, project scripts, or updates.
2. Prefer `range version` and `range --help` as the first sanity checks.
3. Keep paths concrete and avoid suggesting privileged writes unless the chosen install prefix requires them.
4. For stale project-local commands, prefer rerunning `range link .` from the package root.

## Installed Layout

The macOS package installs Range under a versioned payload and points
`current` at the active version:

```text
<prefix>/current/<version> -> ../releases/<version>
<prefix>/current/<version>/range
<prefix>/current/<version>/RangeCore
<prefix>/current/<version>/Skills
```

The shell installer default prefix is `~/.range`, so the CLI is normally:

```text
$HOME/.range/current/<version>/range
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

If `range` is not found, check whether the active install directory is on `PATH`.

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
.range/releases/<version>/range
.range/current/<version>/range
.range/Links/range.package-link.json
```

Different CLI releases can coexist under `.range/releases`. The `.range/current/<version>`
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
- If `RangeCore` is missing, inspect `<prefix>/current/<version>/RangeCore`.
- If bundled skills are missing, inspect `<prefix>/current/<version>/Skills`.
- If project-local commands feel stale, rerun `range link .` from the project root after updating Range.
