#!/bin/sh
set -eu

SOURCE="Resources/RoomDeckAudioBrand.png"
MARK="Resources/RoomDeckAudioMark.png"
MASTER="Resources/RoomDeckAudioIcon.png"
ICONSET="Resources/AppIcon.iconset"
ICNS="Resources/RoomDeckAudio.icns"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/roomdeck-audio-icons.XXXXXX")"

trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

command -v magick >/dev/null 2>&1 || {
    printf '%s\n' 'error: ImageMagick is required (brew install imagemagick)' >&2
    exit 1
}
command -v iconutil >/dev/null 2>&1 || {
    printf '%s\n' 'error: iconutil is required and ships with macOS' >&2
    exit 1
}
test -s "$SOURCE" || {
    printf 'error: source artwork not found: %s\n' "$SOURCE" >&2
    exit 1
}

# Isolate the approved monogram from the source lockup without redrawing it.
magick "$SOURCE" \
    -crop 1254x810+0+0 +repage \
    \( +clone -colorspace gray -level 10%,26% \) \
    -alpha off -compose CopyOpacity -composite \
    -trim +repage "$MARK"

magick -size 1024x1024 xc:none \
    -fill '#0F1117' \
    -draw 'roundrectangle 32,32 992,992 208,208' \
    \( "$MARK" -resize 760x760 \) \
    -gravity center -geometry +0-4 -composite \
    -depth 8 "$MASTER"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

make_icon() {
    size="$1"
    name="$2"
    magick "$MASTER" -resize "${size}x${size}" "$ICONSET/$name"
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET" -o "$ICNS"
printf 'Generated %s, %s, and %s\n' "$MARK" "$MASTER" "$ICNS"
