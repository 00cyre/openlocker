#!/usr/bin/env python3
"""Run the production post-Touch-ID method with deterministic macOS effects.

Keep the actual AppDelegate.grant body in the test: a policy-only replay misses
the platform activation result that used to revoke a successful authentication.
No running app, biometric prompt, or installed protection settings are touched.
"""
from pathlib import Path
import os
import subprocess

root = Path(__file__).resolve().parents[1]
source = (root / "macapp/main.swift").read_text()
start = source.index("    private func grant(")
end = source.index("\n    }\n}", start) + len("\n    }")
fixture = (root / "tests/unlock_focus_fixture.swift").read_text()
build = root / "build/unlock-focus"
build.mkdir(parents=True, exist_ok=True)
generated = build / "main.swift"
generated.write_text(fixture.replace("/* APP_GRANT_METHOD */", source[start:end]))
command = ["xcrun", "swiftc", "-swift-version", "5"]
if cache := os.environ.get("CLANG_MODULE_CACHE_PATH"):
    command += ["-module-cache-path", cache]
binary = build / "unlock-focus-tests"
subprocess.run(command + [str(root / "macapp/LockPolicy.swift"), str(generated), "-o", str(binary)], check=True)
subprocess.run([str(binary)], check=True)
