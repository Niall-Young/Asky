#!/bin/sh
set -eu
cd "$(dirname "$0")"
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
xcrun swiftc -O -target arm64-apple-macosx14.0 main.swift -o text-tools
codesign --force --sign - text-tools
