# Contributor Guide

## Scope And Documentation Ownership

This guide applies to the entire repository and is the operational reference for contributors and coding agents.

- [`README.md`](README.md) is user-facing only: a brief product description, requirements, installation, onboarding and use, common commands, uninstall, and support caveats. Do not add build, architecture, contribution, or release procedures there.
- [`PLAN.md`](PLAN.md) is the durable product source of truth: definition, guarantees, product scope, architecture-level direction, status, and release policy. Do not add contributor command sequences, implementation diaries, or workflow minutiae there.
- `AGENTS.md` owns contributor and agent instructions: documentation ownership, source layout, edit constraints, exact validation commands, generated-file rules, and release operations. Point to `PLAN.md` instead of repeating product prose.

Read `PLAN.md` before changing user-visible behavior, guarantees, storage ordering, supported platforms, installer/updater semantics, architecture boundaries, or release policy. Update it in the same change when those decisions change, and update `README.md` only when user instructions or caveats also change.

## Source Layout

- `Sources/shotd`: executable entry point.
- `Sources/ShotCore/Runtime`: CLI, setup, application paths, LaunchAgent lifecycle, daemon coordination, logs, and updates.
- `Sources/ShotCore/Config` and `State`: validated settings and durable local state.
- `Sources/ShotCore/Watcher`: file events, stabilization, persistent fingerprints, and deduplication.
- `Sources/ShotCore/Media`: media inspection and dimensions.
- `Sources/ShotCore/Image`, `Layout`, `Background`, `Encoding`, and `Video`: media-only processing; do not introduce network, installer, or LaunchAgent concerns.
- `Sources/ShotCore/Output` and `Clipboard`: atomic local output and pasteboard publication.
- `Sources/ShotCore/Storage`: S3, Keychain credentials, bounded asynchronous delivery, and retry state only.
- `Sources/CShotCodecs`: bridge to vendored WebP and AVIF libraries in `CodecKit`.
- `Tests/ShotCoreTests`: unit and integration-oriented XCTest coverage.
- `Packaging`: codec build, installer, onboarding test, and release scripts.
- `.github/workflows/CI.yml` and `.github/workflows/release.yml`: authoritative CI and publication automation.

## Validation Commands

Run from the repository root:

```bash
Packaging/build-codecs.sh
swift build -c release
.build/release/shotd doctor
Packaging/test-onboarding.sh
swift test
```

Run the smallest relevant checks first, then `swift build -c release` before completion. `swift test` requires full Xcode with XCTest, not Command Line Tools alone; if unavailable, still run the release build and report the limitation. Run `git diff --check` and report every command and result.

`doctor` is storage-free. Do not run `storage test`, `storage multipart-test`, or other remote diagnostics against an unknown or production account without the user's explicit consent.

## Edit Constraints

- Keep changes minimal, prefer native Apple frameworks, and do not add runtime package-manager dependencies.
- Preserve the product guarantees in `PLAN.md`, especially serial image output/clipboard behavior and storage-independent local completion.
- Update tests for behavior changes when XCTest is available.
- Keep credentials out of the repository. Production credentials belong in Keychain; inline development credentials are allowed only for a localhost endpoint in a protected local configuration.
- Do not change, remove, or overwrite user configuration, state, Keychain entries, logs, output, source media, or imported backgrounds during install, update, or uninstall unless the CLI explicitly promises it.
- Keep installation and updates scoped to the logged-in GUI user. Never use `sudo`, a LaunchDaemon, or system-wide binary paths.
- Keep the public installer compatible with POSIX `sh`; run an explicit platform check before macOS-specific commands.
- The installer may idempotently manage only shotd's user PATH and generated zsh-completion entries. Keep shell changes minimal and never overwrite unrelated configuration.
- Keep first-time setup interactive and non-technical with safe defaults; preserve explicit non-interactive options for installers and automation.
- Reject equal or nested watch/output directories. Source replacement must preserve format, recheck the fingerprint, write atomically, and avoid watcher loops.
- Keep user-facing processing logs to one concise success line per capture and actionable errors.

## Generated And External Files

- `.build/`, `CodecKit/build-*`, and `CodecKit/AVIF/ext/` are generated and ignored. Regenerate codec outputs with `Packaging/build-codecs.sh`; never commit them.
- `CodecKit` is vendored third-party source. Preserve its licenses, do not bulk-format it, and edit it only for codec behavior or dependency updates.

## Release Operations

- `.github/workflows/release.yml` is authoritative. Do not duplicate or contradict its procedure in `README.md`; keep durable policy in `PLAN.md` aligned with it.
- Releases start only from a manually pushed tag in exact `vYYYY.MM.DD` form. Set `Sources/ShotCore/Runtime/BuildInfo.swift` to exactly the same version before tagging.
- Retain the Apple-silicon artifact, `SHA256SUMS`, the unpacked-binary checksum, codec/architecture/version/dynamic-library checks, and packaged project and third-party licenses.
- Use the configured stable Developer ID with hardened runtime when available; otherwise retain ad-hoc signing. Notarize when all required Apple credentials are configured, but do not make absent notarization credentials block publication.
- Publication may replace assets for a corrected same-day tag. Create the new release or replace its assets successfully before deleting older published releases.
- Keep exactly one active published GitHub Release. Delete older release pages and assets only after successful publication, retain their Git tags, and ensure any earlier failure leaves the prior active release available.
- Do not commit, push, tag, or publish unless the user explicitly requests that operation.

## Completion

Review the final diff without reverting unrelated worktree changes. Report changed files, validation results, unavailable checks, and any intentional documentation overlap.

This guide follows the scoped repository-instruction approach documented by [OpenAI Codex](https://developers.openai.com/codex/agent-configuration/agents-md/) and [OpenCode](https://opencode.ai/docs/rules/).
