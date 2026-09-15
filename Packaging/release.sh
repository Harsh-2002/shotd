#!/bin/zsh
set -euo pipefail

: "${VERSION:?Set VERSION to a vYYYY.MM.DD tag.}"
: "${ARCH:?Set ARCH to arm64.}"

case "$VERSION" in
  v[0-9][0-9][0-9][0-9].[0-9][0-9].[0-9][0-9]) ;;
  *) print -u2 "VERSION must use vYYYY.MM.DD format."; exit 1 ;;
esac
if [[ "$ARCH" != "arm64" ]]; then
  print -u2 "ARCH must be arm64."
  exit 1
fi

root="${0:A:h:h}"
cd "$root"
output="${OUTPUT_DIRECTORY:-$root/dist}"
mkdir -p "$output"

"$root/Packaging/build-codecs.sh" 14.0
swift test --package-path "$root"
swift build --package-path "$root" -c release
binary="$root/.build/release/shotd"

if [[ "$("$binary" version)" != "shotd $VERSION" ]]; then
  print -u2 "BuildInfo.version must match the release tag $VERSION."
  exit 1
fi
if ! file "$binary" | grep -q "$ARCH"; then
  print -u2 "Built binary does not target $ARCH."
  exit 1
fi
if otool -L "$binary" | grep -E '/opt/homebrew|/usr/local|CodecKit' >/dev/null; then
  print -u2 "Release binary contains a non-system dynamic library dependency."
  exit 1
fi

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$binary"
else
  print "No Developer ID identity configured; applying an ad-hoc signature."
  codesign --force --sign - "$binary"
fi
codesign --verify --strict --verbose=2 "$binary"
if ! "$binary" codecs | grep -A 1 '^WEBP$' | grep -q 'available: yes'; then
  print -u2 "WebP codec is unavailable in the release binary."
  exit 1
fi
if ! "$binary" codecs | grep -A 1 '^AVIF$' | grep -q 'available: yes'; then
  print -u2 "AVIF codec is unavailable in the release binary."
  exit 1
fi

archive="$output/shotd-$VERSION-macos-$ARCH.zip"
rm -f "$archive"
package="$output/package"
rm -rf "$package"
mkdir -p "$package/licenses"
cp "$binary" "$package/shotd"
cp "$root/LICENSE" "$package/LICENSE"
cp "$root/THIRD_PARTY_NOTICES.md" "$package/THIRD_PARTY_NOTICES.md"
cp "$root/CodecKit/WebP/COPYING" "$package/licenses/libwebp-COPYING"
cp "$root/CodecKit/AVIF/LICENSE" "$package/licenses/libavif-LICENSE"
aom_license="$root/CodecKit/build-avif/_deps/libaom-src/LICENSE"
if [[ ! -f "$aom_license" ]]; then
  print -u2 "Unable to locate the bundled libaom license."
  exit 1
fi
cp "$aom_license" "$package/licenses/libaom-LICENSE"
ditto -c -k "$package/." "$archive"
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" && -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
  xcrun notarytool submit "$archive" --wait --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD"
else
  print "Release is not notarized. Configure Developer ID and Apple notarization secrets to enable it."
fi
