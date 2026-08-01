#!/bin/sh
set -eu

if swift -e 'import XCTest' >/dev/null 2>&1; then
    exec swift test "$@"
fi

printf '%s\n' 'error: XCTest is unavailable. Install Xcode and select it with xcode-select.' >&2
exit 1
