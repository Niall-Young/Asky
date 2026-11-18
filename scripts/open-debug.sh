#!/bin/bash
# 打开本地 Debug 构建的 Asky.app。传入 --build 时先构建最新代码。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/DerivedData/Build/Products/Debug/Asky.app"

if [[ "${1:-}" == "--build" || ! -d "$APP" ]]; then
    DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" xcodebuild \
        -project "$ROOT/Asky.xcodeproj" \
        -scheme Asky \
        -configuration Debug \
        -derivedDataPath "$ROOT/build/DerivedData" \
        -skipPackageUpdates \
        build
fi

# Match the executable path exactly, including when both Debug and Release are open.
debug_pid() {
    ps -axo pid=,comm= | awk -v exe="$APP/Contents/MacOS/Asky" '{ pid=$1; sub(/^ *[0-9]+ +/, ""); if ($0 == exe) print pid }'
}
pid="$(debug_pid | head -n 1)"
if [[ -n "$pid" && "${1:-}" == "--build" ]]; then
    kill -TERM "$pid"
    for ((i=0; i<50; i++)); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done
    if kill -0 "$pid" 2>/dev/null; then exit 1; fi
    pid=""
fi
if [[ -n "$pid" ]]; then
    osascript -l JavaScript -e "ObjC.import('AppKit'); $.NSRunningApplication.runningApplicationWithProcessIdentifier($pid).activateWithOptions(2)"
else
    open -n "$APP"
fi
