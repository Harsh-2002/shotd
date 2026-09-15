# Agent Guide

## Scope

This guide applies to the entire repository. `shotd` is a macOS 14+ Swift 6 command-line application and GUI-domain LaunchAgent. Preserve its core guarantee: image outputs and clipboard writes remain serialized and never wait for storage delivery.

## Architecture

- `Sources/ShotCore/Runtime`: CLI, LaunchAgent lifecycle, installation, updates, and daemon coordination.
- `Sources/ShotCore/Watcher`: file events, stabilization, and persistent source fingerprints.
- `Sources/ShotCore/Image`, `Layout`, `Background`, `Encoding`, and `Video`: media-only processing; do not introduce network or LaunchAgent concerns here.
- `Sources/ShotCore/Storage`: S3, Keychain credentials, and asynchronous delivery only.
- `Sources/CShotCodecs` bridges the vendored WebP/AVIF libraries. Do not edit `CodecKit` sources unless changing codec behavior or updating a vendored dependency.

## Commands

Run from the repository root:

```bash
Packaging/build-codecs.sh
swift build -c release
.build/release/shotd doctor
swift test
```

`swift test` requires full Xcode with XCTest, not Command Line Tools alone. If it is unavailable, still run the release build and report the test limitation. Storage diagnostics require the user’s configured endpoint and must not be run against an unknown production account without consent.

## Edit Rules

- Keep changes minimal and use native Apple frameworks; do not add runtime package-manager dependencies.
- Update tests for behavior changes when XCTest is available.
- Keep credentials out of the repository. Production credentials belong in Keychain; localhost-only development credentials belong only in a protected local config.
- Do not change, remove, or overwrite a user's config, state, Keychain entries, output, or imported backgrounds during install/update/uninstall unless the CLI explicitly promises it.
- Installation and updates run only for the logged-in GUI user. Never use `sudo`, a LaunchDaemon, shell-profile mutation, or system-wide binary paths.
- Release changes must retain the Apple-silicon artifact, checksum verification, stable Developer ID signing, and notarization. Update `BuildInfo.version` to exactly match a `vYYYY.MM.DD` release tag.

## Generated And External Files

- `.build/`, `CodecKit/build-*`, and `CodecKit/AVIF/ext/` are generated and ignored. Regenerate codec outputs with `Packaging/build-codecs.sh`; never commit them.
- `CodecKit` is vendored third-party source. Preserve its license files and do not bulk-format it.
- `.github/workflows/release.yml` is the authoritative release pipeline. Keep README release instructions aligned with it.

## Completion

Run the smallest relevant validation, then `swift build -c release`. Report commands run, results, and any unavailable checks. Review `git diff --check` before committing.

This guide follows the scoped, repository-specific instruction approach documented by [OpenAI Codex](https://developers.openai.com/codex/agent-configuration/agents-md/) and [OpenCode](https://opencode.ai/docs/rules/).
