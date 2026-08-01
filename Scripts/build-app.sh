#!/bin/sh
set -eu

APP_NAME="RoomDeck Audio"
EXECUTABLE_NAME="RoomDeckAudio"
APP_ARCH="${APP_ARCH:-arm64}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-uk.co.roomdeck.audio}"
OUTPUT_BUNDLE_DIR="dist/${APP_NAME}.app"
STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/roomdeck-audio-build.XXXXXX")"
BUNDLE_DIR="${STAGING_ROOT}/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
APP_VERSION="${APP_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SONOS_AUTH_BASE_URL="${SONOS_AUTH_BASE_URL:-https://example.invalid}"
PRIVACY_POLICY_URL="${PRIVACY_POLICY_URL:-https://example.invalid/privacy}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

trap 'rm -rf "$STAGING_ROOT"' EXIT HUP INT TERM

fail() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

printf '%s' "$APP_VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$' \
    || fail "APP_VERSION must be a semantic version"
printf '%s' "$BUILD_NUMBER" | grep -Eq '^[1-9][0-9]*$' \
    || fail "BUILD_NUMBER must be a positive integer"
printf '%s' "$BUNDLE_IDENTIFIER" | grep -Eq '^[A-Za-z0-9.-]+$' \
    || fail "BUNDLE_IDENTIFIER contains unsupported characters"
printf '%s' "$SONOS_AUTH_BASE_URL" \
    | grep -Eq '^https://[A-Za-z0-9.-]+(:[0-9]+)?(/[A-Za-z0-9._~!$&()*+,;=:@%/-]*)?$' \
    || fail "SONOS_AUTH_BASE_URL must be a plain HTTPS base URL without credentials, query, or fragment"
printf '%s' "$PRIVACY_POLICY_URL" \
    | grep -Eq '^https://[A-Za-z0-9.-]+(:[0-9]+)?(/[A-Za-z0-9._~!$&()*+,;=:@%/-]*)?$' \
    || fail "PRIVACY_POLICY_URL must be a plain HTTPS URL without credentials, query, or fragment"

swift build -c release --arch "$APP_ARCH" --product "$EXECUTABLE_NAME"
BIN_DIR="$(swift build -c release --arch "$APP_ARCH" --show-bin-path)"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "${BIN_DIR}/${EXECUTABLE_NAME}" "${MACOS_DIR}/${EXECUTABLE_NAME}"
cp "Resources/RoomDeckAudio.icns" "${RESOURCES_DIR}/RoomDeckAudio.icns"
cp "Resources/RoomDeckAudioBrand.png" "${RESOURCES_DIR}/RoomDeckAudioBrand.png"
cp "Resources/RoomDeckAudioMark.png" "${RESOURCES_DIR}/RoomDeckAudioMark.png"
cp "Resources/PrivacyInfo.xcprivacy" "${RESOURCES_DIR}/PrivacyInfo.xcprivacy"

cat > "${CONTENTS_DIR}/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>RoomDeck Audio</string>
    <key>CFBundleExecutable</key>
    <string>RoomDeckAudio</string>
    <key>CFBundleIdentifier</key>
    <string>uk.co.roomdeck.audio</string>
    <key>CFBundleIconFile</key>
    <string>RoomDeckAudio</string>
    <key>CFBundleName</key>
    <string>RoomDeck Audio</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>uk.co.roomdeck.audio.sonos-auth</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>roomdeck-audio</string>
                <string>homewave</string>
            </array>
        </dict>
    </array>
    <key>ITSAppUsesNonExemptEncryption</key>
    <false/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.music</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSMultipleInstancesProhibited</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright (c) 2026 RoomDeck Audio contributors</string>
    <key>PrivacyPolicyURL</key>
    <string>https://example.invalid/privacy</string>
    <key>SonosAuthBaseURL</key>
    <string>https://example.invalid</string>
</dict>
</plist>
PLIST

PLIST_FILE="${CONTENTS_DIR}/Info.plist"
plutil -replace CFBundleIdentifier -string "$BUNDLE_IDENTIFIER" "$PLIST_FILE"
plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$PLIST_FILE"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$PLIST_FILE"
plutil -replace SonosAuthBaseURL -string "$SONOS_AUTH_BASE_URL" "$PLIST_FILE"
plutil -replace PrivacyPolicyURL -string "$PRIVACY_POLICY_URL" "$PLIST_FILE"
plutil -lint "$PLIST_FILE" >/dev/null
plutil -lint "${RESOURCES_DIR}/PrivacyInfo.xcprivacy" >/dev/null

xattr -cr "$BUNDLE_DIR"
if [ "$CODE_SIGN_IDENTITY" = "-" ]; then
    codesign --force --sign - "$BUNDLE_DIR"
else
    codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$BUNDLE_DIR"
fi
codesign --verify --deep --strict "$BUNDLE_DIR"

mkdir -p dist
rm -rf "$OUTPUT_BUNDLE_DIR"
ditto "$BUNDLE_DIR" "$OUTPUT_BUNDLE_DIR"
xattr -cr "$OUTPUT_BUNDLE_DIR"
if [ "$CODE_SIGN_IDENTITY" = "-" ]; then
    codesign --force --sign - "$OUTPUT_BUNDLE_DIR"
else
    codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$OUTPUT_BUNDLE_DIR"
fi
codesign --verify --deep --strict "$OUTPUT_BUNDLE_DIR"

printf 'Built %s (%s, version %s build %s)\n' \
    "$OUTPUT_BUNDLE_DIR" "$APP_ARCH" "$APP_VERSION" "$BUILD_NUMBER"
