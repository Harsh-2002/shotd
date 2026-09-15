# shotd

`shotd` is a native macOS background service that turns Apple Screenshot and Screen Recording captures into polished, share-ready media. It preserves capture order, puts finished images on the clipboard, writes an atomic local output, and can upload in the background to S3-compatible storage.

It has no GUI and does not replace Apple's capture workflow.

## Install

Requirements for the prebuilt download are macOS 14 or later on an Apple silicon Mac. Install as the logged-in macOS user, never with `sudo`:

```bash
curl --fail --silent --show-error --location https://raw.githubusercontent.com/Harsh-2002/shotd/main/Packaging/install.sh -o /tmp/shotd-install.sh
zsh /tmp/shotd-install.sh
```

The installer chooses the correct release, verifies its SHA-256 checksum and code signature, then installs it to `~/Library/Application Support/shotd/bin/shotd`. On a first install from Terminal, it starts an interactive setup that asks where screenshots and finished media should go. Each archive also includes shotd's MIT license and bundled-codec license notices.

- A missing `~/Library/Application Support/shotd/config.json` starts first-time setup.
- An existing configuration is an upgrade: it is preserved along with state, logs, imported backgrounds, and Keychain credentials.
- Add `~/Library/Application Support/shotd/bin` to your PATH if you want to call `shotd` directly from a new terminal.
- Set `SHOTD_VERSION=vYYYY.MM.DD` before running the installer to select a particular release.

## First Run

Run the minimal guided setup at any time:

```bash
shotd setup
```

On first use, it asks for the screenshot folder and output folder, shows the one macOS Screenshot setting required, and asks before starting the per-user LaunchAgent. Press Return at either path question to use the safe `~/Pictures/shotd/...` defaults. For automation:

```bash
shotd setup --yes
shotd setup --yes --watch-directory ~/Pictures/shotd/inbox --output-directory ~/Pictures/shotd/output
shotd setup --no-start
```

In macOS, press Shift-Command-5, open **Options**, and choose the shown watch folder as **Save to**. The default is `~/Pictures/shotd/inbox`; output is written to `~/Pictures/shotd/output`.

Keep captures under `~/Pictures` when possible. Desktop, Documents, Downloads, external drives, network folders, and arbitrary wallpaper files can need additional macOS privacy permission. Use `shotd background import /path/to/background.jpg` to copy a protected background into shotd's private application-support directory.

## Everyday Commands

```bash
shotd status
shotd doctor
shotd config validate
shotd codecs
shotd process /path/to/capture.png
shotd background import /path/to/background.jpg
shotd update --check
shotd update
```

`shotd update` downloads the matching architecture archive from GitHub Releases, verifies its SHA-256 checksum, then performs the same transactional installation used by the installer. When Developer ID signing is enabled, it also requires the downloaded binary to have the same signing team as the installed binary.

Configuration is stored at `~/Library/Application Support/shotd/config.json`. Valid changes reload automatically, including changes to `watch.directory`.

## Storage

Production S3 credentials are stored in macOS Keychain:

```bash
shotd storage set-credentials primary
shotd storage test
shotd storage multipart-test
```

Supported endpoints include Amazon S3, Cloudflare R2, MinIO, Backblaze B2 S3, Wasabi, DigitalOcean Spaces, Ceph, Garage, and other Signature V4-compatible services. Local output and clipboard publication never wait for uploads; failed uploads are persisted and retried.

## Build From Source

Source builds require Swift 6, CMake, and macOS 14 or later:

```bash
git clone https://github.com/Harsh-2002/shotd.git
cd shotd
Packaging/build-codecs.sh
swift build -c release
.build/release/shotd setup
```

The release executable statically includes WebP and AVIF codec backends.

## Releases

Versions use calendar format: `vYYYY.MM.DD`. Pushing a matching tag triggers `.github/workflows/release.yml`, which builds a native Apple-silicon (`arm64`) archive, validates codec availability and dynamic dependencies, applies an ad-hoc signature, writes `SHA256SUMS`, and publishes the GitHub release. No Apple Developer membership is required.

Only one published release is active at a time. After a new release has been published successfully, the workflow deletes older release pages and assets while retaining their Git tags.

Before tagging, update `BuildInfo.version` to the exact tag. Developer ID signing and notarization are optional hardening and require these GitHub Actions secrets:

- `DEVELOPER_ID_APPLICATION_P12`
- `DEVELOPER_ID_APPLICATION_P12_PASSWORD`
- `DEVELOPER_ID_APPLICATION`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`

Without Developer ID signing, checksums detect corrupted downloads but cannot prove publisher identity; GitHub's release access remains the trust boundary. If credentials are configured later, keep the signing identity stable so installed copies can verify upgrades. A browser-downloaded, non-notarized archive may require macOS approval before first launch.

## Uninstall

```bash
shotd stop
shotd uninstall
```

This removes the LaunchAgent and installed executable but retains configuration, state, logs, imported backgrounds, output files, and Keychain credentials.

## License

MIT. See [LICENSE](LICENSE).
