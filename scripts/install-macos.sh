#!/bin/bash
set -euo pipefail
umask 077
OPENLOCKER_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$OPENLOCKER_ROOT/scripts/build-native.sh"
OPENLOCKER_DEST="$HOME/Library/Application Support/OpenLocker"
OPENLOCKER_HOSTS="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
mkdir -p "$OPENLOCKER_DEST" "$OPENLOCKER_HOSTS"
ditto "$OPENLOCKER_ROOT/build/OpenLocker.app" "$OPENLOCKER_DEST/OpenLocker.app"
/usr/bin/python3 - "$OPENLOCKER_ROOT/extension-id.txt" "$OPENLOCKER_DEST" "$OPENLOCKER_HOSTS" <<'PY'
import json, pathlib, re, sys
extension_id = pathlib.Path(sys.argv[1]).read_text().strip()
if not re.fullmatch(r'[a-p]{32}', extension_id):
    raise SystemExit('Invalid extension ID')
manifest = {
    'name': 'cc.openlocker.touchid',
    'description': 'OpenLocker Touch ID helper',
    'path': str(pathlib.Path(sys.argv[2]) / 'OpenLocker.app/Contents/MacOS/OpenLocker'),
    'type': 'stdio',
    'allowed_origins': [f'chrome-extension://{extension_id}/'],
}
path = pathlib.Path(sys.argv[3]) / 'cc.openlocker.touchid.json'
temporary = path.with_suffix('.tmp')
temporary.write_text(json.dumps(manifest, indent=2) + '\n')
temporary.chmod(0o600)
temporary.replace(path)
PY
printf '\nOpenLocker helper installed for Google Chrome.\nReturn to OpenLocker settings and click “Check again”.\n'
