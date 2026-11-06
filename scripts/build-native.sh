#!/bin/bash
set -euo pipefail
OPENLOCKER_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'The Touch ID helper can only be built on macOS.' >&2
  exit 1
fi
if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Install Apple's Command Line Tools first: xcode-select --install" >&2
  exit 1
fi
OPENLOCKER_APP="$OPENLOCKER_ROOT/build/OpenLocker.app"
mkdir -p "$OPENLOCKER_APP/Contents/MacOS"
cp "$OPENLOCKER_ROOT/native/Info.plist" "$OPENLOCKER_APP/Contents/Info.plist"
OPENLOCKER_BINARIES=()
for OPENLOCKER_ARCH in ${OPENLOCKER_ARCHS:-$(uname -m)}; do
  case "$OPENLOCKER_ARCH" in arm64|x86_64) ;; *) echo 'Unsupported Mac architecture.' >&2; exit 1 ;; esac
  OPENLOCKER_BINARY="$OPENLOCKER_ROOT/build/OpenLocker-$OPENLOCKER_ARCH"
  xcrun swiftc -O -swift-version 5 -framework LocalAuthentication -framework AppKit \
    -target "$OPENLOCKER_ARCH-apple-macosx13.0" \
    "$OPENLOCKER_ROOT/native/Config.swift" "$OPENLOCKER_ROOT/native/main.swift" \
    -o "$OPENLOCKER_BINARY"
  OPENLOCKER_BINARIES+=("$OPENLOCKER_BINARY")
done
xcrun lipo -create "${OPENLOCKER_BINARIES[@]}" -output "$OPENLOCKER_APP/Contents/MacOS/OpenLocker"
codesign --force --sign - --identifier cc.openlocker.touchid "$OPENLOCKER_APP"
echo "Built $OPENLOCKER_APP"
