#!/bin/bash
set -euo pipefail
OPENLOCKER_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$OPENLOCKER_ROOT"
mkdir -p dist
# Source distribution: native binaries are built locally, never silently downloaded.
python3 - <<'PY'
import pathlib, zipfile
root = pathlib.Path('.')
with zipfile.ZipFile('dist/openlocker-0.1.0.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
    for folder in ['extension', 'native', 'scripts', 'tests', 'docs']:
        for file in sorted((root / folder).rglob('*')):
            if file.is_file() and file.name != '.DS_Store':
                archive.write(file, 'openlocker/' + str(file))
    for name in ['README.md', 'LICENSE', 'PRIVACY.md', 'SECURITY.md', 'extension-id.txt', 'package.json']:
        archive.write(name, 'openlocker/' + name)
print('Created dist/openlocker-0.1.0.zip')
PY
