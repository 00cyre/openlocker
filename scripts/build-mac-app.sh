#!/bin/bash
set -euo pipefail
OPENLOCKER_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$OPENLOCKER_ROOT/scripts/signing.sh"
openlocker_check_release_config
cd "$OPENLOCKER_ROOT"
OPENLOCKER_MAC_APP="${OPENLOCKER_DESKTOP_DEST:-$OPENLOCKER_ROOT/build/desktop/OpenLocker.app}"
# An ad-hoc signature identifies the exact binary. Replacing a live app can
# leave Settings showing an enabled approval for a different code identity.
while IFS= read -r OPENLOCKER_RUNNING_PATH; do
  if [[ "$OPENLOCKER_RUNNING_PATH" == "$OPENLOCKER_MAC_APP/Contents/MacOS/OpenLockerMac" ]]; then
    echo 'OpenLocker is running from this build destination.' >&2
    echo 'Quit it before rebuilding, or set OPENLOCKER_DESKTOP_DEST to a separate app path.' >&2
    exit 1
  fi
done < <(/bin/ps -axo comm=)
bash "$OPENLOCKER_ROOT/scripts/build-native.sh"
mkdir -p "$OPENLOCKER_MAC_APP/Contents/MacOS" "$OPENLOCKER_MAC_APP/Contents/Resources"
OPENLOCKER_MAC_BINARIES=()
for OPENLOCKER_ARCH in ${OPENLOCKER_ARCHS:-$(uname -m)}; do
  case "$OPENLOCKER_ARCH" in arm64|x86_64) ;; *) echo 'Unsupported Mac architecture.' >&2; exit 1 ;; esac
  OPENLOCKER_BINARY="$OPENLOCKER_ROOT/build/OpenLockerMac-$OPENLOCKER_ARCH"
  xcrun swiftc -O -swift-version 5 -framework AppKit -framework ApplicationServices -framework LocalAuthentication -framework ServiceManagement -framework Security -framework CryptoKit \
    -target "$OPENLOCKER_ARCH-apple-macosx13.0" \
    native/Config.swift installer/InstallerEngine.swift shared/CodeIdentity.swift shared/ReleaseUpdater.swift shared/ExtensionInstallation.swift shared/UpdateRecovery.swift macapp/AccessibilityApproval.swift macapp/AccessibilitySetup.swift macapp/ActivationFlow.swift macapp/LockPolicy.swift macapp/WindowShield.swift macapp/WindowObserver.swift macapp/WindowPicker.swift shared/Theme.swift macapp/main.swift \
    -o "$OPENLOCKER_BINARY"
  OPENLOCKER_MAC_BINARIES+=("$OPENLOCKER_BINARY")
done
xcrun lipo -create "${OPENLOCKER_MAC_BINARIES[@]}" -output "$OPENLOCKER_MAC_APP/Contents/MacOS/OpenLockerMac"
cp macapp/Info.plist "$OPENLOCKER_MAC_APP/Contents/Info.plist"
cp installer/AppIcon.icns "$OPENLOCKER_MAC_APP/Contents/Resources/AppIcon.icns"
cp signing/release.cer "$OPENLOCKER_MAC_APP/Contents/Resources/ReleaseCertificate.cer"
mkdir -p "$OPENLOCKER_MAC_APP/Contents/Helpers"
rm -rf "$OPENLOCKER_MAC_APP/Contents/Helpers/OpenLocker.app" "$OPENLOCKER_MAC_APP/Contents/Resources/Chrome"
ditto build/OpenLocker.app "$OPENLOCKER_MAC_APP/Contents/Helpers/OpenLocker.app"
mkdir -p "$OPENLOCKER_MAC_APP/Contents/Resources/Chrome"
ditto extension "$OPENLOCKER_MAC_APP/Contents/Resources/Chrome/extension"
openlocker_sign "$OPENLOCKER_MAC_APP" cc.openlocker.mac
echo "Built $OPENLOCKER_MAC_APP"
