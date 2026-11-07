#!/bin/bash
set -euo pipefail
OPENLOCKER_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$OPENLOCKER_ROOT"
xcrun swiftc -swift-version 5 -framework Security -framework CryptoKit shared/CodeIdentity.swift shared/ReleaseUpdater.swift shared/ExtensionInstallation.swift tests/updater.test.swift -o build/updater-tests
build/updater-tests "$OPENLOCKER_ROOT"
