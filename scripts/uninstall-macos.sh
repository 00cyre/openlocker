#!/bin/bash
set -euo pipefail
# Only remove the exact files installed by OpenLocker. Domain rules belong to
# Chrome; remove the extension there to remove those rules as well.
rm -f "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/cc.openlocker.touchid.json"
rm -rf "$HOME/Library/Application Support/OpenLocker/OpenLocker.app"
rmdir "$HOME/Library/Application Support/OpenLocker" 2>/dev/null || true
printf 'OpenLocker helper removed. Remove the extension in chrome://extensions to stop locking sites.\n'
