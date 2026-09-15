# shotd

`shotd` turns macOS screenshots and screen recordings into polished, share-ready media. Finished images are saved locally and placed on your clipboard automatically. Optional S3 uploads run in the background and never delay paste readiness.

## Requirements

- macOS 14 or newer
- Apple silicon Mac (M1 or newer)

## Install

Open Terminal, paste this command, and press Return:

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/Harsh-2002/shotd/main/Packaging/install.sh)"
```

The installer verifies the download, configures the `shotd` command and completion, and starts guided setup. Press Return to accept the recommended folders, then follow the instruction shown for macOS Screenshot.

## Use

After setup, take screenshots normally with Shift-Command-3, Shift-Command-4, or Shift-Command-5. `shotd` runs quietly in the background.

Useful commands:

```bash
shotd status
shotd doctor
shotd setup
shotd logs
shotd logs --follow
shotd update --check
shotd update
```

## Uninstall

```bash
shotd uninstall
```

Uninstall removes the LaunchAgent and binary but preserves your configuration and data for a future reinstall.

Configuration and output files are retained.

## Build From Source

Developers need Xcode, Swift 6, and CMake:

```bash
Packaging/build-codecs.sh
swift build -c release
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Project direction and release policy are defined in [PLAN.md](PLAN.md). Repository instructions for coding agents are in [AGENTS.md](AGENTS.md).

MIT licensed. See [LICENSE](LICENSE).
