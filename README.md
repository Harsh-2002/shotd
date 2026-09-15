# shotd

`shotd` is a headless native macOS daemon that turns Apple Screenshot and Screen Recording captures into polished, share-ready media.

It watches a directory, applies an adaptive background and presentation treatment, writes an atomic local output, places the image on the clipboard, and optionally uploads to any S3-compatible provider. It has no GUI and does not replace Apple's capture workflow.

## Requirements

- macOS 14 or newer
- Swift 6 toolchain
- CMake, for the bundled WebP and AVIF codecs

## Build

```bash
git clone https://github.com/Harsh-2002/shotd.git
cd shotd
Packaging/build-codecs.sh
swift build -c release
```

The release executable is `.build/release/shotd` and includes static WebP and AVIF codec backends.

## Install

```bash
.build/release/shotd config init
.build/release/shotd install
.build/release/shotd doctor
```

Configure macOS Screenshot to save captures to `~/Pictures/shotd/inbox`. `shotd` writes processed media to `~/Pictures/shotd/output` and runs through the per-user `io.shotd` LaunchAgent.

## Configuration

Configuration is stored at `~/Library/Application Support/shotd/config.json` and reloads automatically after valid changes.

Common commands:

```bash
shotd status
shotd config validate
shotd codecs
shotd doctor
shotd process /path/to/capture.png
shotd background import /path/to/background.jpg
```

For a custom background in a protected folder such as Downloads, use `background import` so shotd copies it to its private Application Support directory instead of requesting repeated macOS folder access.

## Storage

Production S3 credentials are stored in macOS Keychain:

```bash
shotd storage set-credentials primary
shotd storage test
shotd storage multipart-test
```

Supported endpoints include Amazon S3, Cloudflare R2, MinIO, Backblaze B2 S3, Wasabi, DigitalOcean Spaces, Ceph, Garage, and other Signature V4-compatible services. Local output and clipboard publication never wait for uploads; failed uploads are persisted and retried.

## Uninstall

```bash
shotd stop
shotd uninstall
```

This removes the LaunchAgent and installed executable but retains local configuration and output files.

## License

MIT. See [LICENSE](LICENSE).
