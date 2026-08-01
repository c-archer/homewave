#!/bin/sh
set -eu

swift format lint --configuration .swift-format --recursive --strict Sources Tests Package.swift
sh -n Scripts/build-app.sh Scripts/lint.sh Scripts/test.sh Scripts/validate.sh

NODE_BIN="${NODE_BIN:-$(command -v node || true)}"
if [ -n "$NODE_BIN" ]; then
    "$NODE_BIN" --check Workers/roomdeck-audio-auth/src/index.js
    "$NODE_BIN" --check Workers/roomdeck-audio-auth/test/index.test.js
else
    printf '%s\n' 'warning: Node.js not found; Worker syntax checks skipped' >&2
fi
