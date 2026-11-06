#!/bin/bash
set -euo pipefail
OPENLOCKER_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$OPENLOCKER_ROOT"
mkdir -p dist
# Separate source distribution; compiled installers are built by build-installer.sh.
python3 - <<'PY'
import pathlib, zipfile
root = pathlib.Path('.')
with zipfile.ZipFile('dist/OpenLocker-0.1.3-source.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
    for folder in ['extension', 'native', 'shared', 'macapp', 'installer', 'scripts', 'tests', 'docs']:
        for file in sorted((root / folder).rglob('*')):
            if file.is_file() and file.name != '.DS_Store':
                archive.write(file, 'openlocker/' + str(file))
    for name in ['README.md', 'LICENSE', 'PRIVACY.md', 'SECURITY.md', 'extension-id.txt', 'package.json', 'signing/release.cer', 'signing/README.md']:
        archive.write(name, 'openlocker/' + name)
print('Created dist/OpenLocker-0.1.3-source.zip')
PY
