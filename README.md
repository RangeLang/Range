# Range

Range runs `.range` projects by generating a small Swift package and building it with Swift Embedded.

## Download

Install the `range` CLI from the latest GitHub release. macOS is the primary
release target, with Windows and Linux builds published alongside it:

https://github.com/georgetchelidze/Range/releases/latest

Check that it is on your `PATH`:

```sh
range version
```

## Start

Create a project:

```sh
range create MyProject
cd MyProject
```

Run it:

```sh
range run
```

`range run` reads `Project.range`, compiles the project to generated Swift, enables Swift Embedded for that package, and launches it through SwiftPM.
