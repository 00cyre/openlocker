"""Local GUI integration test. Creates only disposable app windows and homes."""
import json
import pathlib
import plistlib
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]


def wait_for(check, timeout=10):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = check()
        if result:
            return result
        time.sleep(0.1)
    raise AssertionError("Timed out waiting for the disposable test window")


with tempfile.TemporaryDirectory(prefix="openlocker-window-update-") as temporary:
    work = pathlib.Path(temporary)
    app = work / "OpenLocker Update Test.app"
    executable = app / "Contents/MacOS/Fixture"
    executable.parent.mkdir(parents=True)
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "cc.openlocker.test-update-window", "CFBundleExecutable": "Fixture",
        "CFBundleName": "OpenLocker Update Test", "CFBundlePackageType": "APPL",
    }))
    subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-framework", "AppKit",
                    str(ROOT / "macapp/WindowShield.swift"), str(ROOT / "tests/update_window_fixture.swift"),
                    "-o", str(executable)], check=True)
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
    children = []
    try:
        target = subprocess.Popen([str(executable), str(work)])
        children.append(target)
        state_file = work / "window-state.json"
        wait_for(state_file.exists)
        before = json.loads(state_file.read_text())
        assert len(before["windows"]) == 2 and all(w["visible"] for w in before["windows"])
        shield = subprocess.Popen([str(executable), str(work), str(target.pid)])
        children.append(shield)
        shield_state = work / "shield-state.json"
        wait_for(lambda: shield_state.exists() and json.loads(shield_state.read_text()).get("covered"))
        # The real installer engine installs full and Chrome-only payloads into
        # temporary home directories; no installed user app is replaced.
        subprocess.run([str(ROOT / "build/installer-tests"), str(ROOT)], check=True, stdout=subprocess.DEVNULL)
        (work / "stop-shield").touch()
        shield.wait(timeout=10)
        (work / "stop-shield").unlink()
        replacement = subprocess.Popen([str(executable), str(work), str(target.pid)])
        children.append(replacement)
        wait_for(lambda: shield_state.exists() and (state := json.loads(shield_state.read_text()))["pid"] == replacement.pid and state["covered"])
        after = json.loads(state_file.read_text())
        assert target.poll() is None, "The protected app terminated during update"
        assert before == after, "A protected window, minimization state, or unsaved draft changed"
        print("PASS: real two-window app kept its PID, window IDs, visibility, and unsaved drafts across installer transactions and blur-process restart")
    finally:
        (work / "stop-shield").touch()
        (work / "stop-window").touch()
        for child in children:
            if child.poll() is None:
                child.wait(timeout=10)
