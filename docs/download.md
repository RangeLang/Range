# Download Neat

Neat is distributed as a command line tool named `neat`.

The easiest way to install it is to download the latest release archive for your platform from:

https://github.com/georgetchelidze/Neat/releases/latest

## macOS

Choose one of these release assets:

- Apple Silicon Macs: `neat-macos-arm64.lang.tar.gz`
- Intel Macs: `neat-macos-x64.lang.tar.gz`

Then open the install package folder and run the installer:

```sh
tar -xzf neat-macos-arm64.lang.tar.gz
cd neat-macos-arm64.lang
./install.sh
neat version
```

Use `neat-macos-x64.lang` in the commands above if you downloaded the Intel archive.

The `.lang` folder is intentionally inspectable before install. It contains:

- `bin/neat`: the Neat CLI executable
- `install.sh`: the installer script
- `uninstall.sh`: the uninstaller script
- `INSTALL_MANIFEST.md`: what gets installed and where

## Linux

Download `neat-linux-x64.tar.gz`, then install the binary:

```sh
tar -xzf neat-linux-x64.tar.gz
sudo mv neat-linux-x64/neat /usr/local/bin/neat
neat version
```

## Windows

Download `neat-windows-x64.zip`, unzip it, and put the extracted folder on your `PATH`.

From PowerShell, you can verify the install with:

```powershell
neat.exe version
```

## Build From Source

If a release binary is not available for your platform, build Neat with Swift:

```sh
git clone https://github.com/georgetchelidze/Neat.git
cd Neat/NeatCLI
swift build -c release --product NeatCLI
```

The built executable is at:

```sh
.build/release/NeatCLI
```

Install it as `neat`:

```sh
sudo cp .build/release/NeatCLI /usr/local/bin/neat
neat version
```

## Create a Project

After installation, create and run a small Neat project:

```sh
neat create HelloNeat
cd HelloNeat
neat run
```

Use `neat --help` to see the available commands.

## Publish a New Download

The repository already includes a GitHub Actions release workflow at `.github/workflows/neatcli-release.yml`.

To publish a new downloadable version:

```sh
git tag v0.1.9
git push origin v0.1.9
```

Replace `v0.1.9` with the version you are releasing. The tag must use the `vMAJOR.MINOR.PATCH` format.

When the tag is pushed, GitHub Actions builds and attaches these release archives:

- `neat-macos-arm64.lang.tar.gz`
- `neat-macos-x64.lang.tar.gz`
- `neat-linux-x64.tar.gz`
- `neat-windows-x64.zip`

Before tagging, make sure the CLI version in `NeatCLI/Sources/NeatCLI/NeatVersion.swift` matches the release version.
