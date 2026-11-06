"""Exercise the compiled host without prompting for, or simulating, a fingerprint."""
import json
import pathlib
import struct
import subprocess
import uuid

root = pathlib.Path(__file__).resolve().parents[1]
binary = root / 'build/OpenLocker.app/Contents/MacOS/OpenLocker'
origin = f'chrome-extension://{(root / "extension-id.txt").read_text().strip()}/'

def run(payload, caller=origin):
    return subprocess.run([str(binary), caller], input=payload, capture_output=True, timeout=10)

def packet(message):
    data = json.dumps(message).encode()
    return struct.pack('<I', len(data)) + data

def decode(result):
    assert result.returncode == 0, result.stderr.decode()
    length, = struct.unpack('<I', result.stdout[:4])
    assert length == len(result.stdout[4:])
    return json.loads(result.stdout[4:])

request_id = str(uuid.uuid4())
status = decode(run(packet({'id': request_id, 'operation': 'status'})))
assert status['id'] == request_id
assert isinstance(status['available'], bool)
assert run(packet({'id': request_id, 'operation': 'status'}), 'chrome-extension://untrusted/').returncode != 0
assert run(struct.pack('<I', 17000)).returncode != 0
assert run(struct.pack('<I', 100) + b'{}').returncode != 0
assert run(packet({'id': 'invalid', 'operation': 'status'})).returncode != 0
assert decode(run(packet({'id': request_id, 'operation': 'delete'})))['success'] is False
assert decode(run(packet({'id': request_id, 'operation': 'authenticate', 'domain': 'bad\nreason'})))['success'] is False
print('Native protocol: 7 checks passed. Touch ID available:', status['available'])
