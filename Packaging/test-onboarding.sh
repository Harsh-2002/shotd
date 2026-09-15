#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
binary="$root/.build/release/shotd"
home="$(mktemp -d "${TMPDIR:-/tmp}/shotd-onboarding.XXXXXX")"
trap 'rm -rf "$home"' EXIT

export HOME="$home"
export CFFIXED_USER_HOME="$home"
export NO_COLOR=1
export SHOTD_BINARY="$binary"

"$binary" setup --yes --no-start >/dev/null
settings="$home/Library/Application Support/shotd/settings.json"
plutil -replace watch.directory -string '~/Pictures/shotd/My\ Screens' "$settings"
plutil -replace output.directory -string '~/Pictures/shotd/My\ Screens/shotd' "$settings"

expect <<'EXPECT'
set timeout 30
spawn $env(SHOTD_BINARY) setup --no-start
expect "Screenshot folder"
send "\r"
expect "Finished media folder"
send "\r"
expect "Finished media must be outside the screenshot folder."
expect "Finished media folder"
send "\r"
expect "Replace original screenshots?"
send "\r"
expect "Background \[keep/desktop/custom/solid\]"
send "\r"
expect "Compress screenshots?"
send "n\r"
expect "Upload copies to S3-compatible storage?"
send "n\r"
expect "Setup ready"
expect eof
set result [wait]
exit [lindex $result 3]
EXPECT

"$binary" config validate >/dev/null
test -f "$settings"
test "$(plutil -extract watch.directory raw "$settings")" = "~/Pictures/shotd/My Screens"

plutil -replace image.format -string preserve "$settings"
plutil -remove image.compression "$settings"

expect <<'EXPECT'
set timeout 30
spawn $env(SHOTD_BINARY) setup --no-start
expect "Screenshot folder"
send "\r"
expect "Finished media folder"
send "\r"
expect "Replace original screenshots?"
send "\r"
expect "Background \[keep/desktop/custom/solid\]"
send "\r"
expect "Compress screenshots?"
send "\r"
expect "Output format"
send "\r"
expect "Upload copies to S3-compatible storage?"
send "n\r"
expect "Setup ready"
expect eof
set result [wait]
exit [lindex $result 3]
EXPECT

test "$(plutil -extract image.format raw "$settings")" = "preserve"
if plutil -extract image.compression raw "$settings" >/dev/null 2>&1; then
  print -u2 "Preserve format unexpectedly gained a compression mode."
  exit 1
fi
