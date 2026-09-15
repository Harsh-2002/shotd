# shotd Product Plan

This document is the durable source of truth for the product definition, guarantees, architecture-level direction, implemented status, and release policy. User instructions belong in `README.md`; contributor procedures belong in `AGENTS.md`.

## Definition

`shotd` is a native macOS command-line application and per-user background LaunchAgent that turns files created by Apple's screenshot controls into polished, share-ready media. Apple owns capture, selection, recording, annotation, and permissions; `shotd` owns presentation, encoding, local output, clipboard publication, and optional delivery.

The normal experience is capture, then paste or share. No editor or persistent graphical application is required.

Supported releases target macOS 14 or newer on Apple silicon (`arm64`). The implementation uses Swift 6, native Apple frameworks, and bundled WebP and AVIF codecs.

## Product Guarantees

These are invariants:

- A finished local file is the primary result.
- Still-image output and image clipboard publication are serialized. Video uses an independent serial queue.
- Local output and clipboard readiness never wait for storage delivery.
- Finished files are written atomically; partial output must not be exposed.
- Uploads and persisted retries are asynchronous and bounded. Their failure does not invalidate local success.
- Files are stabilized and fingerprinted so duplicate events and daemon restarts do not duplicate work.
- Watch and output directories must be non-empty locations under the current user's home and must not be equal or contain one another.
- Keeping sources is the default. Deletion or replacement occurs only after its configured success condition and a final fingerprint check. Replacement preserves source format and cannot create a watcher loop.
- Invalid configuration changes do not replace the active configuration.
- Processing is quiet while idle and emits one concise success line per capture plus actionable errors.

## Product Scope

Screenshots support adaptive background, padding, placement, corner, shadow, color, and size treatment without forcing a fixed aspect ratio. Backgrounds may be the desktop wallpaper, an imported image, a solid color, or a gradient. Image output supports PNG, WebP, AVIF, HEIC, JPEG, and source-format preservation; a lossless request must use verified lossless encoding or a configured fallback.

MOV and MP4 recordings receive the same presentation treatment and are emitted atomically as MP4 or MOV using hardware-accelerated H.264 or HEVC. Frame rate and audio are preserved when possible and enabled. Image clipboard output is paste-ready media; video clipboard output is a local file URL when enabled.

Optional S3-compatible delivery sends the actual encoded result. It supports path or virtual-host addressing, public or presigned URLs, multipart transfer, bounded retries, and HTTPS endpoints. Plain HTTP and inline development credentials are allowed only for localhost development.

## Safety And Data

The canonical versioned settings file is `~/Library/Application Support/shotd/settings.json`. Settings writes are validated, atomic, permissioned `0600`, and read back before acceptance. The former `config.json` is migration input only: an existing canonical file wins, invalid legacy data remains untouched, and the old file is removed only after the new file is safely verified.

Production storage credentials live in the user's macOS Keychain and must not enter settings, logs, source control, release assets, or command arguments. Storage diagnostics that contact a configured endpoint require deliberate user action.

Installation, updates, runtime, and uninstall are user-scoped. They must not require `sudo`, install a LaunchDaemon, or write system-wide binary paths. Install and update preserve settings, state, Keychain items, logs, imported backgrounds, source media, and output media. Uninstall removes managed runtime components but is not a purge.

First-time setup remains an interactive, non-technical flow with safe local-only defaults. It validates folder separation and imported backgrounds, enables storage only after consent to a remote verification, and retains explicit non-interactive options for installation and automation. Failed or cancelled setup must roll back newly created credentials and imported backgrounds.

## Architecture Direction

The package has a small executable over a reusable core. Responsibilities remain separated across runtime and lifecycle, validated configuration and state, event-driven watching and stabilization, media inspection and processing, atomic output and clipboard publication, and asynchronous storage delivery.

Media processing must not acquire network, installer, or LaunchAgent responsibilities. Storage owns its networking, Keychain access, delivery concurrency, and retry state. Concurrency boundaries remain explicit through serial media queues, actor-isolated state, main-actor UI frameworks, atomic files, and bounded upload tasks. The daemon should consume effectively no CPU while idle, and network access belongs only to explicit updates and storage.

Native Apple frameworks remain preferred. Runtime package-manager dependencies are out of scope; vendored codec changes are limited to codec behavior or dependency updates.

## Installation And Updates

The public installer remains POSIX `sh`, checks Darwin and `arm64` before using macOS tools, verifies release checksums and code signatures, and atomically installs the per-user binary. Existing valid settings bypass onboarding; invalid settings enter interactive repair when possible and otherwise fail without replacing user data. The installer may manage only shotd-owned user PATH and zsh-completion integration and must not overwrite unrelated shell configuration.

Updates compare calendar versions and also compare the published binary checksum for corrected builds using the same tag. Before replacement they verify archive and binary checksums, code signatures, and matching Developer ID teams when either binary has a Developer ID identity.

## Release Policy

- Releases use exact `vYYYY.MM.DD` tags, and the embedded version must match the tag.
- Publication begins only from a manually pushed calendar tag; ordinary branch pushes do not publish.
- The supported artifact is an Apple-silicon archive with archive and unpacked-binary checksums, required license material, verified bundled codecs, and no non-system dynamic-library dependencies.
- Developer ID signing and notarization are optional hardening. When configured, releases retain the stable signing identity and are notarized; otherwise an ad-hoc signature plus GitHub-hosted checksums is the implemented trust boundary.
- A corrected build may reuse the current day's tag and is distinguished by its binary checksum.
- There may be only one active published GitHub Release. Older release pages and assets are retired only after the new publication succeeds; their Git tags remain. Any earlier failure leaves the existing release available.

## Status And Direction

The end-to-end product is implemented: watcher and restart deduplication, image and video rendering, adaptive presentation, atomic output, clipboard publication, source-retention safeguards, S3 and multipart delivery with retries, Keychain credentials, setup and migration, LaunchAgent lifecycle, diagnostics, updates, CI, and release packaging.

Near-term work should harden this capture-to-paste product rather than broaden it:

- Improve reliability, diagnostics, and regression coverage for real screenshot and recording edge cases.
- Expand deterministic media, exact lossless, and visual validation.
- Validate S3 compatibility only against explicitly configured non-production services.
- Improve signing and notarization coverage when credentials are available.
- Measure large-media performance and memory before adding processing features.

## Non-Goals

`shotd` is not a capture UI, editor, Apple Markup replacement, menu-bar application, synchronous uploader, general cloud-sync tool, privileged or multi-user service, or cross-platform product under the current plan. It must not add unrelated network behavior to media-processing modules.

Changes to user-visible behavior, guarantees, supported platforms, install/update semantics, architecture boundaries, or release policy must update this document and keep user-facing instructions consistent.
