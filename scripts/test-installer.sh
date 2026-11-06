#!/bin/bash
set -euo pipefail
OPENLOCKER_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$OPENLOCKER_ROOT"
xcrun swiftc -swift-version 5 -framework CryptoKit -framework Security native/Config.swift shared/CodeIdentity.swift installer/InstallerEngine.swift \
  tests/installer.test.swift -o build/installer-tests
build/installer-tests "$OPENLOCKER_ROOT"
xcrun lipo "build/installer/Install OpenLocker.app/Contents/MacOS/InstallOpenLocker" -verify_arch arm64 x86_64
xcrun lipo "build/installer/Install OpenLocker.app/Contents/Resources/Payload/OpenLocker.app/Contents/MacOS/OpenLocker" -verify_arch arm64 x86_64
xcrun lipo "build/installer/Install OpenLocker.app/Contents/Resources/Payload/Desktop/OpenLocker.app/Contents/MacOS/OpenLockerMac" -verify_arch arm64 x86_64
codesign --verify --deep --strict "build/installer/Install OpenLocker.app"
hdiutil verify dist/OpenLocker-0.1.4-macOS.dmg

xcrun swiftc -swift-version 5 -framework CryptoKit -framework Security native/Config.swift shared/CodeIdentity.swift installer/InstallerEngine.swift tests/accessibility_upgrade.test.swift -o build/accessibility-upgrade-tests
build/accessibility-upgrade-tests "$OPENLOCKER_ROOT"
bash scripts/test-updater.sh
