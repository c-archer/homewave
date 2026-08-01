#!/bin/sh
set -eu

MASTER="Resources/RoomDeckAudioIcon.png"
MARK="Resources/RoomDeckAudioMark.png"
LOCKUP="Resources/RoomDeckAudioBrand.png"
ICNS="Resources/RoomDeckAudio.icns"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/roomdeck-audio-brand-check.XXXXXX")"

trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

fail() {
    printf 'brand-assets: %s\n' "$1" >&2
    exit 1
}

dimensions() {
    width="$(sips -g pixelWidth "$1" | awk '/pixelWidth/ { print $2 }')"
    height="$(sips -g pixelHeight "$1" | awk '/pixelHeight/ { print $2 }')"
    printf '%sx%s' "$width" "$height"
}

test -s "$LOCKUP" || fail "full lockup is missing"
test -s "$MARK" || fail "RD monogram is missing"
test -s "$MASTER" || fail "launcher master is missing"
test -s "$ICNS" || fail "macOS icon container is missing"

test "$(dimensions "$LOCKUP")" = "1254x1254" || fail "full lockup dimensions changed"
test "$(dimensions "$MARK")" = "748x483" || fail "RD monogram dimensions changed"
test "$(dimensions "$MASTER")" = "1024x1024" || fail "launcher master must be 1024 px"

test "$(sips -g hasAlpha "$MARK" | awk '/hasAlpha/ { print $2 }')" = "yes" \
    || fail "RD monogram must preserve transparency"
test "$(sips -g hasAlpha "$MASTER" | awk '/hasAlpha/ { print $2 }')" = "yes" \
    || fail "launcher master must have transparent corners"

iconutil -c iconset "$ICNS" -o "$TMP_DIR/AppIcon.iconset"
test "$(find "$TMP_DIR/AppIcon.iconset" -type f -name '*.png' | wc -l | tr -d ' ')" = "10" \
    || fail "macOS icon container does not include every required size"

printf '%s\n' 'Brand assets verified.'
