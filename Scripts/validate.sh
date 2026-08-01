#!/bin/sh
set -eu

./Scripts/lint.sh
./Scripts/legal-audit.sh
./Scripts/verify-brand-assets.sh
./Scripts/test.sh

NODE_BIN="${NODE_BIN:-$(command -v node || true)}"
if [ -z "$NODE_BIN" ]; then
    printf '%s\n' 'error: Node.js 20 or later is required for Worker tests' >&2
    exit 1
fi
"$NODE_BIN" --test Workers/roomdeck-audio-auth/test/index.test.js

./Scripts/build-app.sh
