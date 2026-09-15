#!/bin/zsh
set -euo pipefail

repository="Harsh-2002/shotd"
if [[ "$(sysctl -n hw.optional.arm64 2>/dev/null || print 0)" != "1" ]]; then
  print -u2 "shotd releases currently support Apple silicon Macs only."
  exit 1
fi
architecture="arm64"

temporary="$(mktemp -d "${TMPDIR:-/tmp}/shotd-install.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT

if [[ -n "${SHOTD_VERSION:-}" ]]; then
  version="$SHOTD_VERSION"
else
  version="$(curl --fail --silent --show-error --location -H 'Accept: application/vnd.github+json' -H 'User-Agent: shotd-installer' "https://api.github.com/repos/$repository/releases/latest" | plutil -extract tag_name raw -)"
fi

archive="shotd-$version-macos-$architecture.zip"
base_url="https://github.com/$repository/releases/download/$version"
curl --fail --silent --show-error --location "$base_url/SHA256SUMS" -o "$temporary/SHA256SUMS"
curl --fail --silent --show-error --location "$base_url/$archive" -o "$temporary/$archive"

expected=""
while read -r checksum filename; do
  filename="${filename#\*}"
  if [[ "$filename" == "$archive" ]]; then
    expected="$checksum"
    break
  fi
done < "$temporary/SHA256SUMS"
actual="$(shasum -a 256 "$temporary/$archive")"
actual="${actual%% *}"
if [[ -z "$expected" || "$actual" != "$expected" ]]; then
  print -u2 "The downloaded shotd archive failed SHA-256 verification."
  exit 1
fi

mkdir "$temporary/unpacked"
ditto -x -k "$temporary/$archive" "$temporary/unpacked"
binary="$temporary/unpacked/shotd"
if [[ ! -x "$binary" ]]; then
  print -u2 "The release archive does not contain an executable shotd binary."
  exit 1
fi
codesign --verify --strict "$binary"

installed="$HOME/Library/Application Support/shotd/bin/shotd"
if [[ -e "$installed" ]]; then
  current_team="$(codesign --display --verbose=4 "$installed" 2>&1 | grep '^TeamIdentifier=' | cut -d= -f2)"
  candidate_team="$(codesign --display --verbose=4 "$binary" 2>&1 | grep '^TeamIdentifier=' | cut -d= -f2)"
  if [[ "$current_team" != "not set" || "$candidate_team" != "not set" ]] && [[ -z "$current_team" || "$current_team" != "$candidate_team" ]]; then
    print -u2 "The downloaded binary is not signed by the same Developer ID team as the installed shotd."
    exit 1
  fi
fi

configuration="$HOME/Library/Application Support/shotd/config.json"
if [[ -f "$configuration" ]]; then
  "$binary" install
  print "shotd $version installed as an upgrade. Your existing configuration was preserved."
elif [[ -t 0 ]]; then
  "$binary" setup
else
  "$binary" setup --yes
fi
