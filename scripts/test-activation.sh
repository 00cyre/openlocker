#!/bin/bash
set -euo pipefail
OPENLOCKER_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$OPENLOCKER_ROOT"
mkdir -p build
xcrun swiftc -swift-version 5 macapp/ActivationFlow.swift tests/activation_regression.test.swift -o build/activation-regression
build/activation-regression
