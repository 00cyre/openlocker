#!/bin/bash
set -euo pipefail
# Quit OpenLocker and turn off Start at login before running this script.
# Only remove the exact files installed by OpenLocker. Domain rules belong to
# Chrome; remove the extension there to remove those rules as well.
rm -f "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/cc.openlocker.touchid.json"
rm -rf "$HOME/Library/Application Support/OpenLocker/OpenLocker.app"
rm -rf "$HOME/Library/Application Support/OpenLocker/extension"
if [[ -f "$HOME/Applications/OpenLocker.app/Contents/Info.plist" ]] && [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$HOME/Applications/OpenLocker.app/Contents/Info.plist")" == cc.openlocker.mac ]]; then
  rm -rf "$HOME/Applications/OpenLocker.app"
fi
rmdir "$HOME/Library/Application Support/OpenLocker" 2>/dev/null || true
printf 'OpenLocker app and helper removed; protected-apps.json is preserved. Remove the extension in chrome://extensions to stop locking sites.\n'
