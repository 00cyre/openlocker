"""Import the existing CI identity into an isolated temporary keychain."""
import base64
import os
from pathlib import Path
import subprocess

keychain = Path(os.environ["OPENLOCKER_SIGNING_KEYCHAIN"])
identity = keychain.with_suffix(".p12")
password = os.environ["OPENLOCKER_SIGNING_PASSWORD"]

def run(arguments):
    result = subprocess.run(arguments, capture_output=True)
    if result.returncode:
        # Commands contain credentials. Never print argv or their raw errors.
        raise SystemExit("Could not prepare the release signing keychain.")

try:
    identity.write_bytes(base64.b64decode(os.environ["OPENLOCKER_SIGNING_P12"], validate=True))
    identity.chmod(0o600)
    run(["security", "create-keychain", "-p", password, str(keychain)])
    run(["security", "set-keychain-settings", "-lut", "21600", str(keychain)])
    run(["security", "unlock-keychain", "-p", password, str(keychain)])
    run(["security", "import", str(identity), "-k", str(keychain), "-P", password, "-T", "/usr/bin/codesign"])
    run(["security", "set-key-partition-list", "-S", "apple-tool:,apple:", "-s", "-k", password, str(keychain)])
finally:
    identity.unlink(missing_ok=True)
print("Release identity imported into an isolated keychain.")
