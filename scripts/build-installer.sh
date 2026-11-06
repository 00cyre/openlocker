#!/bin/bash
set -euo pipefail
OPENLOCKER_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$OPENLOCKER_ROOT/scripts/signing.sh"
openlocker_check_release_config
cd "$OPENLOCKER_ROOT"
if [[ "$(uname -s)" != Darwin ]]; then echo 'Build the installer on macOS.' >&2; exit 1; fi
OPENLOCKER_STAGE="$OPENLOCKER_ROOT/build/installer"
OPENLOCKER_APP="$OPENLOCKER_STAGE/Install OpenLocker.app"
mkdir -p "$OPENLOCKER_APP/Contents/MacOS" "$OPENLOCKER_APP/Contents/Resources/Payload" "$OPENLOCKER_ROOT/dist"
# Ship native code for both Mac architectures. No compiler is needed by users.
OPENLOCKER_ARCHS="arm64 x86_64" OPENLOCKER_DESKTOP_DEST="$OPENLOCKER_ROOT/build/release-desktop/OpenLocker.app" bash scripts/build-mac-app.sh
for OPENLOCKER_ARCH in arm64 x86_64; do
  xcrun swiftc -O -swift-version 5 -framework AppKit -framework CryptoKit -framework Security \
    -target "$OPENLOCKER_ARCH-apple-macosx13.0" \
    native/Config.swift shared/CodeIdentity.swift installer/InstallerEngine.swift installer/main.swift \
    -o "$OPENLOCKER_ROOT/build/InstallOpenLocker-$OPENLOCKER_ARCH"
done
xcrun lipo -create build/InstallOpenLocker-arm64 build/InstallOpenLocker-x86_64 -output "$OPENLOCKER_APP/Contents/MacOS/InstallOpenLocker"
cp installer/Info.plist "$OPENLOCKER_APP/Contents/Info.plist"
cp installer/AppIcon.icns "$OPENLOCKER_APP/Contents/Resources/AppIcon.icns"
# Start with a clean payload so removed source files do not survive a rebuild.
rm -rf "$OPENLOCKER_APP/Contents/Resources/Payload/extension" "$OPENLOCKER_APP/Contents/Resources/Payload/OpenLocker.app"
ditto extension "$OPENLOCKER_APP/Contents/Resources/Payload/extension"
ditto build/OpenLocker.app "$OPENLOCKER_APP/Contents/Resources/Payload/OpenLocker.app"
rm -rf "$OPENLOCKER_APP/Contents/Resources/Payload/Desktop"
mkdir -p "$OPENLOCKER_APP/Contents/Resources/Payload/Desktop"
ditto build/release-desktop/OpenLocker.app "$OPENLOCKER_APP/Contents/Resources/Payload/Desktop/OpenLocker.app"
openlocker_sign "$OPENLOCKER_APP" cc.openlocker.installer
codesign --verify --deep --strict "$OPENLOCKER_APP"
cp installer/Start-Here.html "$OPENLOCKER_STAGE/Start Here.html"
hdiutil create -ov -format UDZO -volname 'OpenLocker 0.1.2' \
  -srcfolder "$OPENLOCKER_STAGE" "$OPENLOCKER_ROOT/dist/OpenLocker-0.1.2-macOS.dmg"
if [[ "${OPENLOCKER_RELEASE:-0}" == 1 ]]; then
  openlocker_sign "$OPENLOCKER_ROOT/dist/OpenLocker-0.1.2-macOS.dmg" cc.openlocker.disk
fi
# Useful for environments that prefer extracting a zip rather than mounting a disk.
ditto -c -k --sequesterRsrc --keepParent "$OPENLOCKER_APP" "$OPENLOCKER_ROOT/dist/OpenLocker-0.1.2-macOS.zip"
shasum -a 256 dist/OpenLocker-0.1.2-macOS.dmg dist/OpenLocker-0.1.2-macOS.zip | sed 's|dist/||' > dist/SHA256SUMS.txt
printf '\nInstaller ready: dist/OpenLocker-0.1.2-macOS.dmg\n'
