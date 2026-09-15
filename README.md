# shotd

`shotd` turns macOS screenshots and screen recordings into polished, share-ready media. Finished files are saved locally and images are copied to the clipboard automatically. Optional S3-compatible uploads run in the background and never delay paste readiness.

## Requirements

- macOS 14 or newer
- Apple silicon Mac (M1 or newer)

## Install

Open Terminal, paste this command, and press Return:

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/Harsh-2002/shotd/main/Packaging/install.sh)"
```

Do not use `sudo`. The installer verifies the download, configures the `shotd` command and zsh completion, and starts guided setup.

## Onboarding And Use

Setup asks about folders, presentation, image format, and optional S3-compatible storage. Press Return to accept safe local-only defaults, then select the folder it shows in macOS Screenshot options.

Take screenshots normally with Shift-Command-3, Shift-Command-4, or Shift-Command-5. `shotd` runs quietly in the background; rerun `shotd setup` whenever you want to change its guided settings.

Common commands:

```bash
shotd status          # Show LaunchAgent status
shotd doctor          # Check the local installation
shotd setup           # Review or change setup
shotd logs            # Show recent activity and errors
shotd logs --follow   # Follow new log entries
shotd update --check  # Check for an update
shotd update          # Install the latest release
```

## Support Notes

- Settings are stored at `~/Library/Application Support/shotd/settings.json`. A legacy `config.json` is migrated only after validation.
- `shotd doctor` does not contact storage. The explicit `shotd storage test` and `shotd storage multipart-test` commands use the configured endpoint and credentials.
- If macOS blocks first launch, approve `shotd` in System Settings > Privacy & Security, then run the installer again.
- Optional upload failures do not invalidate a finished local file or clipboard write.

## Uninstall

```bash
shotd uninstall
```

Uninstall removes the LaunchAgent and managed binary but preserves settings, logs, imported backgrounds, source media, and output media for a future reinstall. It is not a data purge.

MIT licensed. See [LICENSE](LICENSE).
