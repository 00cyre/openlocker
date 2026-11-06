#!/bin/bash
set -euo pipefail
OPENLOCKER_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$OPENLOCKER_ROOT"
mkdir -p build
xcrun swiftc -swift-version 5 macapp/LockPolicy.swift tests/mac_policy.test.swift -o build/mac-policy-tests
build/mac-policy-tests

bash scripts/test-activation.sh

xcrun swiftc -swift-version 5 macapp/AccessibilityApproval.swift tests/accessibility_approval.test.swift -o build/accessibility-approval-tests
build/accessibility-approval-tests
xcrun swiftc -swift-version 5 shared/UpdateRecovery.swift tests/update_recovery.test.swift -o build/update-recovery-tests
build/update-recovery-tests
