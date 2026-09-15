#!/bin/sh
set -eu

repository="Harsh-2002/shotd"
if [ "$(uname -s)" != "Darwin" ] || [ "$(uname -m)" != "arm64" ]; then
  printf '%s\n' "shotd releases currently support Apple silicon Macs only." >&2
  exit 1
fi
architecture="arm64"

temporary="$(mktemp -d "${TMPDIR:-/tmp}/shotd-install.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT

if [ -n "${SHOTD_VERSION:-}" ]; then
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
  if [ "$filename" = "$archive" ]; then
    expected="$checksum"
    break
  fi
done < "$temporary/SHA256SUMS"
actual="$(shasum -a 256 "$temporary/$archive")"
actual="${actual%% *}"
if [ -z "$expected" ] || [ "$actual" != "$expected" ]; then
  printf '%s\n' "The downloaded shotd archive failed SHA-256 verification." >&2
  exit 1
fi

mkdir "$temporary/unpacked"
ditto -x -k "$temporary/$archive" "$temporary/unpacked"
binary="$temporary/unpacked/shotd"
if [ ! -x "$binary" ]; then
  printf '%s\n' "The release archive does not contain an executable shotd binary." >&2
  exit 1
fi
codesign --verify --strict "$binary"

installed="$HOME/Library/Application Support/shotd/bin/shotd"
if [ -e "$installed" ]; then
  current_team="$(codesign --display --verbose=4 "$installed" 2>&1 | grep '^TeamIdentifier=' | cut -d= -f2)"
  candidate_team="$(codesign --display --verbose=4 "$binary" 2>&1 | grep '^TeamIdentifier=' | cut -d= -f2)"
  if { [ "$current_team" != "not set" ] || [ "$candidate_team" != "not set" ]; } && { [ -z "$current_team" ] || [ "$current_team" != "$candidate_team" ]; }; then
    printf '%s\n' "The downloaded binary is not signed by the same Developer ID team as the installed shotd." >&2
    exit 1
  fi
fi

configuration="$HOME/Library/Application Support/shotd/config.json"
if [ -f "$configuration" ]; then
  "$binary" install
  result="shotd $version upgraded. Your existing configuration was preserved."
elif [ -t 0 ]; then
  "$binary" setup
  result="shotd $version installed."
else
  "$binary" setup --yes
  result="shotd $version installed."
fi

mkdir -p "$HOME/.local/bin" "$HOME/.local/share/zsh/site-functions"
ln -sf "$installed" "$HOME/.local/bin/shotd"
"$installed" completions zsh > "$HOME/.local/share/zsh/site-functions/_shotd"

profile="$HOME/.zprofile"
path_line='export PATH="$HOME/.local/bin:$PATH"'
fpath_line='fpath=("$HOME/.local/share/zsh/site-functions" $fpath)'
grep -Fqx "$path_line" "$profile" 2>/dev/null || printf '\n%s\n' "$path_line" >> "$profile"
grep -Fqx "$fpath_line" "$profile" 2>/dev/null || printf '%s\nautoload -Uz compinit && compinit\n' "$fpath_line" >> "$profile"

printf '\n%s\n' "$result"
printf '%s\n' "Open a new Terminal and run: shotd doctor"
printf '%s\n' "Do not use sudo."
printf '%s\n' "If macOS blocks first launch, approve shotd in System Settings > Privacy & Security, then run this installer again."
