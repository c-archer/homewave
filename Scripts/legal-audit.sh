#!/bin/sh
set -eu

fail() {
    printf 'legal-audit: %s\n' "$1" >&2
    exit 1
}

if rg -n -i \
    'play\.sonos\.com/api/content|x-sonos-|ssdp|upnp|soapaction|avtransport|renderingcontrol' \
    Sources; then
    fail "private catalogue or local reverse-engineered control code is present"
fi

retired_brand='Home''Wave'
if rg -n "$retired_brand" \
    Package.swift Sources Tests Scripts Workers README.md CHANGELOG.md CONTRIBUTING.md \
    PRIVACY.md SECURITY.md LEGAL.md THIRD_PARTY_NOTICES.md docs .github LICENSE; then
    fail "retired product branding is still present in a published text file"
fi

if find Resources -type f \
    | rg -i '/(sonos|spotify|bbc|apple[-_ ]?music|amazon[-_ ]?music|deezer|audible|soundcloud)' >/dev/null; then
    fail "a third-party service or station asset appears to be bundled"
fi

for required in LEGAL.md PRIVACY.md THIRD_PARTY_NOTICES.md docs/ASSET_PROVENANCE.md Resources/PrivacyInfo.xcprivacy; do
    test -s "$required" || fail "$required is required for public releases"
done

plutil -lint Resources/PrivacyInfo.xcprivacy >/dev/null \
    || fail "the Apple privacy manifest is invalid"

printf '%s\n' 'Legal-release guard passed.'
